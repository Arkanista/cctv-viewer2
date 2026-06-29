#include "systemstats.h"
#include "qmlav/src/qmlavdemuxer.h"
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QDebug>
#include <QProcess>
#include <QFileInfo>
#include <QRegularExpression>
#include <QLibrary>
#include <unistd.h>
#include <sys/types.h>

// NVML Types
typedef void* nvmlDevice_t;
typedef enum nvmlReturn_enum {
    NVML_SUCCESS = 0,
    NVML_ERROR_NOT_SUPPORTED = 3,
} nvmlReturn_t;

typedef struct nvmlUtilization_st {
    unsigned int gpu;
    unsigned int memory;
} nvmlUtilization_t;

typedef struct nvmlProcessInfo_st {
    unsigned int pid;
    unsigned long long usedGpuMemory;
} nvmlProcessInfo_t;

typedef struct nvmlProcessUtilizationSample_st {
    unsigned int pid;
    unsigned long long timeStamp;
    unsigned int smUtil;
    unsigned int memUtil;
    unsigned int encUtil;
    unsigned int decUtil;
} nvmlProcessUtilizationSample_t;

typedef nvmlReturn_t (*fn_nvmlInit)(void);
typedef nvmlReturn_t (*fn_nvmlShutdown)(void);
typedef nvmlReturn_t (*fn_nvmlDeviceGetCount)(unsigned int *deviceCount);
typedef nvmlReturn_t (*fn_nvmlDeviceGetHandleByIndex)(unsigned int index, nvmlDevice_t *device);
typedef nvmlReturn_t (*fn_nvmlDeviceGetUtilizationRates)(nvmlDevice_t device, nvmlUtilization_t *rates);
typedef nvmlReturn_t (*fn_nvmlDeviceGetGraphicsRunningProcesses)(nvmlDevice_t device, unsigned int *infoCount, nvmlProcessInfo_t *infos);
typedef nvmlReturn_t (*fn_nvmlDeviceGetComputeRunningProcesses)(nvmlDevice_t device, unsigned int *infoCount, nvmlProcessInfo_t *infos);
typedef nvmlReturn_t (*fn_nvmlDeviceGetProcessUtilization)(nvmlDevice_t device, nvmlProcessUtilizationSample_t *utilization, unsigned int *processSamplesCount, unsigned long long lastSeenTimeStamp);

struct StatsWorker::NvmlContext {
    QLibrary lib;
    bool initialized = false;
    bool loadFailed = false;

    fn_nvmlInit nvmlInit = nullptr;
    fn_nvmlShutdown nvmlShutdown = nullptr;
    fn_nvmlDeviceGetCount nvmlDeviceGetCount = nullptr;
    fn_nvmlDeviceGetHandleByIndex nvmlDeviceGetHandleByIndex = nullptr;
    fn_nvmlDeviceGetUtilizationRates nvmlDeviceGetUtilizationRates = nullptr;
    fn_nvmlDeviceGetGraphicsRunningProcesses nvmlDeviceGetGraphicsRunningProcesses = nullptr;
    fn_nvmlDeviceGetComputeRunningProcesses nvmlDeviceGetComputeRunningProcesses = nullptr;
    fn_nvmlDeviceGetProcessUtilization nvmlDeviceGetProcessUtilization = nullptr;

    ~NvmlContext() {
        if (initialized && nvmlShutdown) {
            nvmlShutdown();
        }
        if (lib.isLoaded()) {
            lib.unload();
        }
    }

    bool ensureInitialized() {
        if (initialized) return true;
        if (loadFailed) return false;

        lib.setFileName("nvidia-ml");
        if (!lib.load()) {
            loadFailed = true;
            return false;
        }

        nvmlInit = (fn_nvmlInit)lib.resolve("nvmlInit");
        nvmlShutdown = (fn_nvmlShutdown)lib.resolve("nvmlShutdown");
        nvmlDeviceGetCount = (fn_nvmlDeviceGetCount)lib.resolve("nvmlDeviceGetCount");
        nvmlDeviceGetHandleByIndex = (fn_nvmlDeviceGetHandleByIndex)lib.resolve("nvmlDeviceGetHandleByIndex");
        nvmlDeviceGetUtilizationRates = (fn_nvmlDeviceGetUtilizationRates)lib.resolve("nvmlDeviceGetUtilizationRates");
        nvmlDeviceGetGraphicsRunningProcesses = (fn_nvmlDeviceGetGraphicsRunningProcesses)lib.resolve("nvmlDeviceGetGraphicsRunningProcesses");
        nvmlDeviceGetComputeRunningProcesses = (fn_nvmlDeviceGetComputeRunningProcesses)lib.resolve("nvmlDeviceGetComputeRunningProcesses");
        nvmlDeviceGetProcessUtilization = (fn_nvmlDeviceGetProcessUtilization)lib.resolve("nvmlDeviceGetProcessUtilization");

        if (!nvmlInit || !nvmlShutdown || !nvmlDeviceGetCount || !nvmlDeviceGetHandleByIndex ||
            !nvmlDeviceGetUtilizationRates || !nvmlDeviceGetGraphicsRunningProcesses || !nvmlDeviceGetComputeRunningProcesses) {
            lib.unload();
            loadFailed = true;
            return false;
        }

        if (nvmlInit() != NVML_SUCCESS) {
            lib.unload();
            loadFailed = true;
            return false;
        }

        initialized = true;
        return true;
    }
};

StatsWorker::StatsWorker(QObject *parent)
    : QObject(parent)
{
    m_netTimer.start();
    m_gpuTimer.start();
    m_nvml = new NvmlContext();
}

StatsWorker::~StatsWorker()
{
    delete m_nvml;

    qint64 selfPid = getpid();
    uid_t myUid = getuid();
    QString shmDir = "/dev/shm";
    if (!QDir(shmDir).exists() || !QFileInfo(shmDir).isWritable()) {
        shmDir = QDir::tempPath();
    }
    QString myNetFile = QString("%1/kvision-net-%2-%3").arg(shmDir).arg(myUid).arg(selfPid);
    QString myGpuFile = QString("%1/kvision-gpu-%2-%3").arg(shmDir).arg(myUid).arg(selfPid);
    QString myVramFile = QString("%1/kvision-vram-%2-%3").arg(shmDir).arg(myUid).arg(selfPid);
    QFile::remove(myNetFile);
    QFile::remove(myGpuFile);
    QFile::remove(myVramFile);
}

void StatsWorker::doWork()
{
    if (m_pidCacheTicks <= 0) {
        m_cachedPids = getProgramPids();
        m_pidCacheTicks = 5; // Refresh PID list every 5 seconds to reduce CPU/RAM overhead
    }
    m_pidCacheTicks--;

    QVector<qint64> pids = m_cachedPids;
    qint64 selfPid = getpid();

    bool active = m_uiActive.load(std::memory_order_relaxed);

    double cpu = 0.0;
    double ram = 0.0;
    double gpu = 0.0;
    double vram = 0.0;
    double net = 0.0;

    if (active) {
        calculateCpuAndRam(pids, cpu, ram);
        calculateGpuAndVram(pids, gpu, vram);
        calculateNetUsage(pids, net);

        emit workDone(cpu, gpu, ram, vram, net);
    } else {
        calculateGpuAndVram(QVector<qint64>{selfPid}, gpu, vram);
        calculateNetUsage(QVector<qint64>{selfPid}, net);
    }
}

SystemStats::SystemStats(QObject *parent)
    : QObject(parent)
{
    m_worker = new StatsWorker();
    m_workerThread = new QThread(this);
    m_worker->moveToThread(m_workerThread);

    connect(m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);

    m_timer = new QTimer(this);
    connect(m_timer, &QTimer::timeout, m_worker, &StatsWorker::doWork);
    connect(m_worker, &StatsWorker::workDone, this, &SystemStats::onWorkDone);

    m_workerThread->start();
    m_timer->start(1000); // Always run the timer to report background stats!
}

SystemStats::~SystemStats()
{
    m_timer->stop();
    m_workerThread->quit();
    m_workerThread->wait();
}

void SystemStats::onWorkDone(double cpu, double gpu, double ram, double vram, double net)
{
    m_cpuUsage = cpu;
    m_gpuUsage = gpu;
    m_ramUsage = ram;
    m_vramUsage = vram;
    m_netUsage = net;
    emit statsChanged();
}

bool SystemStats::active() const
{
    return m_active;
}

void SystemStats::setActive(bool active)
{
    if (m_active == active) return;
    m_active = active;
    m_worker->setUiActive(active);

    if (m_active) {
        QMetaObject::invokeMethod(m_worker, "doWork", Qt::QueuedConnection);
    } else {
        m_cpuUsage = 0.0;
        m_gpuUsage = 0.0;
        m_ramUsage = 0.0;
        m_vramUsage = 0.0;
        m_netUsage = 0.0;
        emit statsChanged();
    }
    emit activeChanged();
}

QVector<qint64> StatsWorker::getProgramPids()
{
    QVector<qint64> pids;
    qint64 selfPid = getpid();
    pids.append(selfPid);

    uid_t myUid = getuid();
    QString selfExe = QFile::symLinkTarget(QString("/proc/%1/exe").arg(selfPid));

    struct ProcessInfo {
        qint64 pid;
        qint64 ppid;
        uid_t uid;
        QString name;
        QString exePath;
    };
    QVector<ProcessInfo> allProcs;

    QDir procDir("/proc");
    QStringList entries = procDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : entries) {
        bool ok = false;
        qint64 pid = entry.toLongLong(&ok);
        if (!ok || pid == selfPid) continue;

        ProcessInfo info;
        info.pid = pid;
        info.ppid = -1;
        info.uid = -1;

        QFile statusFile(QString("/proc/%1/status").arg(pid));
        if (statusFile.open(QIODevice::ReadOnly)) {
            QString content = QString::fromUtf8(statusFile.readAll());
            statusFile.close();
            QStringList lines = content.split('\n');
            for (const QString &line : lines) {
                if (line.startsWith("Uid:")) {
                    int colonIdx = line.indexOf(':');
                    if (colonIdx != -1) {
                        QString valStr = line.mid(colonIdx + 1).trimmed();
                        int firstWsIdx = -1;
                        for (int i = 0; i < valStr.length(); ++i) {
                            if (valStr[i].isSpace()) {
                                firstWsIdx = i;
                                break;
                            }
                        }
                        if (firstWsIdx != -1) {
                            valStr = valStr.left(firstWsIdx);
                        }
                        info.uid = valStr.toUInt();
                    }
                } else if (line.startsWith("PPid:")) {
                    int colonIdx = line.indexOf(':');
                    if (colonIdx != -1) {
                        QString valStr = line.mid(colonIdx + 1).trimmed();
                        int firstWsIdx = -1;
                        for (int i = 0; i < valStr.length(); ++i) {
                            if (valStr[i].isSpace()) {
                                firstWsIdx = i;
                                break;
                            }
                        }
                        if (firstWsIdx != -1) {
                            valStr = valStr.left(firstWsIdx);
                        }
                        info.ppid = valStr.toLongLong();
                    }
                }
            }
        }

        if (info.uid != myUid) continue;

        // check executable name via symlink first
        QString exePath = QFile::symLinkTarget(QString("/proc/%1/exe").arg(pid));
        info.exePath = exePath;
        info.name = QFileInfo(exePath).fileName();

        // fallback to cmdline
        if (info.name.isEmpty()) {
            QFile cmdFile(QString("/proc/%1/cmdline").arg(pid));
            if (cmdFile.open(QIODevice::ReadOnly)) {
                QByteArray cmdline = cmdFile.readAll();
                cmdFile.close();
                if (cmdline.contains("kvision") || cmdline.contains("cctv-viewer2") || cmdline.contains("cctv-viewer")) {
                    info.name = "kvision";
                }
            }
        }

        allProcs.append(info);
    }

    // Pass 1: Find all direct cctv-viewer processes or same executable instances
    for (const ProcessInfo &info : allProcs) {
        bool matches = false;
        if (!selfExe.isEmpty() && !info.exePath.isEmpty() && info.exePath == selfExe) {
            matches = true;
        } else if (info.name == "kvision" || info.name == "cctv-viewer2" || info.name == "cctv-viewer") {
            matches = true;
        }

        if (matches) {
            if (!pids.contains(info.pid)) {
                pids.append(info.pid);
            }
        }
    }

    // Pass 2: Iteratively add all child processes of any PID currently in our pids list
    bool addedAny = true;
    while (addedAny) {
        addedAny = false;
        for (const ProcessInfo &info : allProcs) {
            if (!pids.contains(info.pid) && pids.contains(info.ppid)) {
                pids.append(info.pid);
                addedAny = true;
            }
        }
    }

    return pids;
}

void StatsWorker::calculateCpuAndRam(const QVector<qint64> &pids, double &cpu, double &ram)
{
    // 1. Read total system CPU time
    qint64 totalCpuTime = 0;
    QFile statFile("/proc/stat");
    if (statFile.open(QIODevice::ReadOnly)) {
        QTextStream stream(&statFile);
        QString line = stream.readLine();
        statFile.close();
        if (line.startsWith("cpu ")) {
            QString valStr = line.mid(4).trimmed();
            QStringList parts = valStr.split(QChar(' '), Qt::SkipEmptyParts);
            for (int i = 0; i < parts.size() && i < 8; ++i) { // sum user to dirty/steal
                totalCpuTime += parts[i].toLongLong();
            }
        }
    }

    // 2. Read process CPU times and RSS
    qint64 processCpuTimeSum = 0;
    double ramUsageSum = 0;

    QHash<qint64, qint64> currentProcessCpuTimes;

    for (qint64 pid : pids) {
        // Read /proc/<pid>/stat
        QFile pStatFile(QString("/proc/%1/stat").arg(pid));
        if (pStatFile.open(QIODevice::ReadOnly)) {
            QTextStream stream(&pStatFile);
            QString content = stream.readAll();
            pStatFile.close();

            QStringList parts = content.split(' ');
            if (parts.size() > 17) {
                // utime=14, stime=15, cutime=16, cstime=17 (0-based: 13, 14, 15, 16)
                qint64 utime = parts[13].toLongLong();
                qint64 stime = parts[14].toLongLong();
                qint64 cutime = parts[15].toLongLong();
                qint64 cstime = parts[16].toLongLong();
                qint64 procTime = utime + stime + cutime + cstime;
                currentProcessCpuTimes[pid] = procTime;

                if (m_prevProcessCpuTimes.contains(pid)) {
                    processCpuTimeSum += (procTime - m_prevProcessCpuTimes[pid]);
                }
            }
        }

        // Read /proc/<pid>/status for RAM (VmRSS)
        QFile pStatusFile(QString("/proc/%1/status").arg(pid));
        if (pStatusFile.open(QIODevice::ReadOnly)) {
            QString content = QString::fromUtf8(pStatusFile.readAll());
            pStatusFile.close();
            QStringList lines = content.split('\n');
            for (const QString &line : lines) {
                if (line.startsWith("VmRSS:")) {
                    int colonIdx = line.indexOf(':');
                    if (colonIdx != -1) {
                        QString valStr = line.mid(colonIdx + 1).trimmed();
                        int spaceIdx = valStr.indexOf(' ');
                        if (spaceIdx != -1) {
                            valStr = valStr.left(spaceIdx);
                        }
                        ramUsageSum += valStr.toDouble() / 1024.0; // convert kB to MB
                    }
                }
            }
        }
    }

    // Calculate CPU %
    if (m_prevTotalCpuTime > 0 && totalCpuTime > m_prevTotalCpuTime) {
        qint64 sysDelta = totalCpuTime - m_prevTotalCpuTime;
        cpu = (static_cast<double>(processCpuTimeSum) / sysDelta) * 100.0;
        if (cpu < 0.0) cpu = 0.0;
        if (cpu > 100.0) cpu = 100.0;
    } else {
        cpu = 0.0;
    }

    m_prevTotalCpuTime = totalCpuTime;
    m_prevProcessCpuTimes = currentProcessCpuTimes;
    ram = ramUsageSum;
}

void StatsWorker::calculateGpuAndVram(const QVector<qint64> &pids, double &gpu, double &vram)
{
    gpu = 0.0;
    vram = 0.0;

    qint64 selfPid = getpid();
    uid_t myUid = getuid();
    QString shmDir = "/dev/shm";
    if (!QDir(shmDir).exists() || !QFileInfo(shmDir).isWritable()) {
        shmDir = QDir::tempPath();
    }

    // Step A: Calculate OWN GPU and VRAM
    double ownGpu = 0.0;
    double ownVram = 0.0;

    // 1. Try Nvidia NVML first for selfPid
    if (m_nvml && m_nvml->ensureInitialized()) {
        unsigned int devCount = 0;
        if (m_nvml->nvmlDeviceGetCount(&devCount) == NVML_SUCCESS && devCount > 0) {
            double vramSum = 0.0;
            double gpuSum = 0.0;
            bool processGpuSuccess = false;

            for (unsigned int i = 0; i < devCount; ++i) {
                nvmlDevice_t device = nullptr;
                if (m_nvml->nvmlDeviceGetHandleByIndex(i, &device) != NVML_SUCCESS) continue;

                // Sum process memory (VRAM)
                unsigned int procCount = 128;
                nvmlProcessInfo_t procInfos[128];
                
                // Graphics processes
                if (m_nvml->nvmlDeviceGetGraphicsRunningProcesses(device, &procCount, procInfos) == NVML_SUCCESS) {
                    for (unsigned int p = 0; p < procCount; ++p) {
                        if (procInfos[p].pid == selfPid) {
                            vramSum += procInfos[p].usedGpuMemory / (1024.0 * 1024.0); // B to MiB
                        }
                    }
                }
                
                // Compute processes
                procCount = 128;
                if (m_nvml->nvmlDeviceGetComputeRunningProcesses(device, &procCount, procInfos) == NVML_SUCCESS) {
                    for (unsigned int p = 0; p < procCount; ++p) {
                        if (procInfos[p].pid == selfPid) {
                            vramSum += procInfos[p].usedGpuMemory / (1024.0 * 1024.0); // B to MiB
                        }
                    }
                }

                // Process specific GPU utilization
                if (m_nvml->nvmlDeviceGetProcessUtilization) {
                    unsigned int sampleCount = 128;
                    nvmlProcessUtilizationSample_t samples[128];
                    if (m_nvml->nvmlDeviceGetProcessUtilization(device, samples, &sampleCount, 0) == NVML_SUCCESS) {
                        double devGpuSum = 0.0;
                        for (unsigned int s = 0; s < sampleCount; ++s) {
                            if (samples[s].pid == selfPid) {
                                devGpuSum += samples[s].smUtil + samples[s].decUtil + samples[s].encUtil; // Combined GPU % (SM + Decoder + Encoder)
                                processGpuSuccess = true;
                            }
                        }
                        gpuSum += devGpuSum;
                    }
                }
            }

            ownVram = vramSum;

            if (processGpuSuccess) {
                ownGpu = gpuSum;
                if (ownGpu > 100.0) ownGpu = 100.0;
            }
        }
    }

    // 2. Try DRM Client Stats (for AMD, Intel, and fallback Nvidia) for selfPid
    if (ownGpu <= 0.0) {
        double drmVramSum = 0.0;
        qint64 totalEngineDeltaNs = 0;
        QHash<QString, qint64> nextDrmEngineTimes;
        bool hasDrmClients = false;

        QString fdInfoPath = QString("/proc/%1/fdinfo").arg(selfPid);
        QDir dir(fdInfoPath);
        if (dir.exists()) {
            QStringList files = dir.entryList(QDir::Files);
            for (const QString &fdName : files) {
                QFile f(dir.absoluteFilePath(fdName));
                if (!f.open(QIODevice::ReadOnly)) continue;

                QTextStream stream(&f);
                bool isDrm = false;
                qint64 fdEngineTime = 0;

                while (!stream.atEnd()) {
                    QString line = stream.readLine().trimmed();
                    if (line.startsWith("drm-driver:")) {
                        isDrm = true;
                        hasDrmClients = true;
                    } else if (line.startsWith("drm-engine-")) {
                        int colonIdx = line.indexOf(':');
                        if (colonIdx != -1) {
                            QString valStr = line.mid(colonIdx + 1).trimmed();
                            int spaceIdx = -1;
                            for (int i = 0; i < valStr.length(); ++i) {
                                if (valStr[i].isSpace()) {
                                    spaceIdx = i;
                                    break;
                                }
                            }
                            if (spaceIdx != -1) {
                                valStr = valStr.left(spaceIdx);
                            }
                            bool ok = false;
                            qint64 val = valStr.toLongLong(&ok);
                            if (ok) {
                                fdEngineTime += val;
                            }
                        }
                    } else if (line.startsWith("drm-memory-vram:")) {
                        int colonIdx = line.indexOf(':');
                        if (colonIdx != -1) {
                            QString valStr = line.mid(colonIdx + 1).trimmed();
                            QString unit = "";
                            int spaceIdx = -1;
                            for (int i = 0; i < valStr.length(); ++i) {
                                if (valStr[i].isSpace()) {
                                    spaceIdx = i;
                                    break;
                                }
                            }
                            if (spaceIdx != -1) {
                                unit = valStr.mid(spaceIdx + 1).trimmed();
                                valStr = valStr.left(spaceIdx);
                            }
                            bool ok = false;
                            double val = valStr.toDouble(&ok);
                            if (ok) {
                                if (unit.toLower() == "kib" || unit.isEmpty()) {
                                    val /= 1024.0;
                                } else if (unit.toLower() == "gib") {
                                    val *= 1024.0;
                                } else if (unit.toLower() == "b") {
                                    val /= (1024.0 * 1024.0);
                                }
                                drmVramSum += val;
                            }
                        }
                    }
                }
                f.close();

                if (isDrm) {
                    QString key = QString("%1:%2").arg(selfPid).arg(fdName);
                    nextDrmEngineTimes[key] = fdEngineTime;
                    if (m_prevDrmEngineTimes.contains(key)) {
                        qint64 delta = fdEngineTime - m_prevDrmEngineTimes[key];
                        if (delta > 0) {
                            totalEngineDeltaNs += delta;
                        }
                    }
                }
            }
        }

        qint64 elapsedMs = m_gpuTimer.restart();
        if (elapsedMs <= 0) elapsedMs = 1000;

        m_prevDrmEngineTimes = nextDrmEngineTimes;

        if (hasDrmClients) {
            if (ownVram <= 0.0) {
                ownVram = drmVramSum;
            }

            double drmGpu = 0.0;
            if (totalEngineDeltaNs > 0) {
                drmGpu = (static_cast<double>(totalEngineDeltaNs) / (elapsedMs * 1000000.0)) * 100.0;
                if (drmGpu > 100.0) drmGpu = 100.0;
            }
            ownGpu = drmGpu;
        }
    }

    // 3. Try System-wide NVML Fallback (if we are Nvidia but have no process stats)
    if (ownGpu <= 0.0 && m_nvml && m_nvml->initialized) {
        unsigned int devCount = 0;
        if (m_nvml->nvmlDeviceGetCount(&devCount) == NVML_SUCCESS && devCount > 0) {
            nvmlDevice_t device = nullptr;
            if (m_nvml->nvmlDeviceGetHandleByIndex(0, &device) == NVML_SUCCESS) {
                nvmlUtilization_t utilization;
                if (m_nvml->nvmlDeviceGetUtilizationRates(device, &utilization) == NVML_SUCCESS) {
                    ownGpu = utilization.gpu;
                }
            }
        }
    }

    // 4. Try AMD/Intel System-wide sysfs fallback
    if (ownGpu <= 0.0) {
        QFile amdGpuBusy("/sys/class/drm/card0/device/gpu_busy_percent");
        if (amdGpuBusy.exists() && amdGpuBusy.open(QIODevice::ReadOnly)) {
            QTextStream stream(&amdGpuBusy);
            ownGpu = stream.readAll().trimmed().toDouble();
            amdGpuBusy.close();

            if (ownVram <= 0.0) {
                QFile amdVram("/sys/class/drm/card0/device/mem_info_vram_used");
                if (amdVram.exists() && amdVram.open(QIODevice::ReadOnly)) {
                    QTextStream vramStream(&amdVram);
                    ownVram = vramStream.readAll().trimmed().toDouble() / (1024.0 * 1024.0); // B to MiB
                    amdVram.close();
                }
            }
        }
    }

    // Step B: Write OWN GPU and VRAM to shared memory files
    QString myGpuFile = QString("%1/kvision-gpu-%2-%3").arg(shmDir).arg(myUid).arg(selfPid);
    QFile fGpu(myGpuFile);
    if (fGpu.open(QIODevice::WriteOnly)) {
        QTextStream stream(&fGpu);
        stream << QString::number(ownGpu, 'f', 2);
        fGpu.close();
    }

    QString myVramFile = QString("%1/kvision-vram-%2-%3").arg(shmDir).arg(myUid).arg(selfPid);
    QFile fVram(myVramFile);
    if (fVram.open(QIODevice::WriteOnly)) {
        QTextStream stream(&fVram);
        stream << QString::number(ownVram, 'f', 2);
        fVram.close();
    }

    // Step C: Sum GPU and VRAM of all active PIDs
    double totalGpu = 0.0;
    double totalVram = 0.0;

    for (qint64 pid : pids) {
        if (pid == selfPid) {
            totalGpu += ownGpu;
            totalVram += ownVram;
        } else {
            QString otherGpuFile = QString("%1/kvision-gpu-%2-%3").arg(shmDir).arg(myUid).arg(pid);
            QFile fOtherGpu(otherGpuFile);
            if (fOtherGpu.open(QIODevice::ReadOnly)) {
                double otherGpu = 0.0;
                QTextStream streamOther(&fOtherGpu);
                streamOther >> otherGpu;
                totalGpu += otherGpu;
                fOtherGpu.close();
            }

            QString otherVramFile = QString("%1/kvision-vram-%2-%3").arg(shmDir).arg(myUid).arg(pid);
            QFile fOtherVram(otherVramFile);
            if (fOtherVram.open(QIODevice::ReadOnly)) {
                double otherVram = 0.0;
                QTextStream streamOther(&fOtherVram);
                streamOther >> otherVram;
                totalVram += otherVram;
                fOtherVram.close();
            }
        }
    }

    if (totalGpu > 100.0) totalGpu = 100.0;
    gpu = totalGpu;
    vram = totalVram;
}

void StatsWorker::calculateNetUsage(const QVector<qint64> &pids, double &net)
{
    qint64 diffBytes = g_networkBytesAccumulator.exchange(0, std::memory_order_relaxed);
    qint64 elapsedMs = m_netTimer.restart();
    if (elapsedMs <= 0) elapsedMs = 1000;

    // Convert to bits per second (bps)
    double bps = (static_cast<double>(diffBytes) * 8.0) / (elapsedMs / 1000.0);

    qint64 selfPid = getpid();
    uid_t myUid = getuid();

    // Determine secure shared memory directory
    QString shmDir = "/dev/shm";
    if (!QDir(shmDir).exists() || !QFileInfo(shmDir).isWritable()) {
        shmDir = QDir::tempPath();
    }

    // Write own network bps to shared file
    QString myNetFile = QString("%1/kvision-net-%2-%3").arg(shmDir).arg(myUid).arg(selfPid);
    QFile f(myNetFile);
    if (f.open(QIODevice::WriteOnly)) {
        QTextStream stream(&f);
        stream << QString::number(bps, 'f', 1);
        f.close();
    }

    // Sum network bps of all active pids
    double totalBps = 0.0;
    for (qint64 pid : pids) {
        if (pid == selfPid) {
            totalBps += bps;
        } else {
            QString otherNetFile = QString("%1/kvision-net-%2-%3").arg(shmDir).arg(myUid).arg(pid);
            QFile fOther(otherNetFile);
            if (fOther.open(QIODevice::ReadOnly)) {
                double otherBps = 0.0;
                QTextStream streamOther(&fOther);
                streamOther >> otherBps;
                totalBps += otherBps;
                fOther.close();
            }
        }
    }

    // Convert to Megabits per second (Mbps)
    net = totalBps / 1000000.0;

    // Clean up stale shared files of processes that are no longer running
    static int cleanTicks = 0;
    if (++cleanTicks >= 10) {
        cleanTicks = 0;
        QDir dir(shmDir);
        QString prefixNet = QString("kvision-net-%1-").arg(myUid);
        QString prefixGpu = QString("kvision-gpu-%1-").arg(myUid);
        QString prefixVram = QString("kvision-vram-%1-").arg(myUid);
        
        QStringList netFiles = dir.entryList(QStringList() << prefixNet + "*", QDir::Files);
        for (const QString &fileName : netFiles) {
            QString pidPart = fileName.mid(prefixNet.length());
            bool ok = false;
            qint64 pid = pidPart.toLongLong(&ok);
            if (ok && !pids.contains(pid) && pid != selfPid) {
                dir.remove(fileName);
            }
        }
        
        QStringList gpuFiles = dir.entryList(QStringList() << prefixGpu + "*", QDir::Files);
        for (const QString &fileName : gpuFiles) {
            QString pidPart = fileName.mid(prefixGpu.length());
            bool ok = false;
            qint64 pid = pidPart.toLongLong(&ok);
            if (ok && !pids.contains(pid) && pid != selfPid) {
                dir.remove(fileName);
            }
        }

        QStringList vramFiles = dir.entryList(QStringList() << prefixVram + "*", QDir::Files);
        for (const QString &fileName : vramFiles) {
            QString pidPart = fileName.mid(prefixVram.length());
            bool ok = false;
            qint64 pid = pidPart.toLongLong(&ok);
            if (ok && !pids.contains(pid) && pid != selfPid) {
                dir.remove(fileName);
            }
        }
    }
}
