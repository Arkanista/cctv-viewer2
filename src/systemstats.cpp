#include "systemstats.h"
#include "qmlav/src/qmlavdemuxer.h"
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QDebug>
#include <QProcess>
#include <QFileInfo>
#include <QRegularExpression>
#include <unistd.h>
#include <sys/types.h>

StatsWorker::StatsWorker(QObject *parent)
    : QObject(parent)
{
    m_netTimer.start();
}

void StatsWorker::doWork()
{
    QVector<qint64> pids = getProgramPids();
    double cpu = 0.0;
    double ram = 0.0;
    double gpu = 0.0;
    double vram = 0.0;
    double net = 0.0;

    calculateCpuAndRam(pids, cpu, ram);
    calculateGpuAndVram(pids, gpu, vram);
    calculateNetUsage(net);

    emit workDone(cpu, gpu, ram, vram, net);
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
    m_timer->start(1000); // every 1s

    // Trigger first work asynchronously
    QMetaObject::invokeMethod(m_worker, "doWork", Qt::QueuedConnection);
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

QVector<qint64> StatsWorker::getProgramPids()
{
    QVector<qint64> pids;
    qint64 selfPid = getpid();
    pids.append(selfPid);

    uid_t myUid = getuid();

    struct ProcessInfo {
        qint64 pid;
        qint64 ppid;
        uid_t uid;
        QString name;
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
                    QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
                    if (parts.size() > 1) {
                        info.uid = parts[1].toUInt();
                    }
                } else if (line.startsWith("PPid:")) {
                    QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
                    if (parts.size() > 1) {
                        info.ppid = parts[1].toLongLong();
                    }
                }
            }
        }

        if (info.uid != myUid) continue;

        // check executable name via symlink first
        QString exePath = QFile::symLinkTarget(QString("/proc/%1/exe").arg(pid));
        info.name = QFileInfo(exePath).fileName();

        // fallback to cmdline
        if (info.name.isEmpty()) {
            QFile cmdFile(QString("/proc/%1/cmdline").arg(pid));
            if (cmdFile.open(QIODevice::ReadOnly)) {
                QByteArray cmdline = cmdFile.readAll();
                cmdFile.close();
                if (cmdline.contains("cctv-viewer2") || cmdline.contains("cctv-viewer")) {
                    info.name = "cctv-viewer2";
                }
            }
        }

        allProcs.append(info);
    }

    // Pass 1: Find all direct cctv-viewer processes
    for (const ProcessInfo &info : allProcs) {
        if (info.name == "cctv-viewer2" || info.name == "cctv-viewer") {
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
            QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
            for (int i = 1; i < parts.size() && i <= 8; ++i) { // sum user to dirty/steal
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
                    QStringList parts = line.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
                    if (parts.size() > 1) {
                        ramUsageSum += parts[1].toDouble() / 1024.0; // convert kB to MB
                    }
                    break;
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
    // Try Nvidia first
    QFile nvidiaSmi("/usr/bin/nvidia-smi");
    if (nvidiaSmi.exists()) {
        // Query overall GPU utilization
        QProcess procGpu;
        procGpu.start("nvidia-smi", QStringList() << "--query-gpu=utilization.gpu" << "--format=csv,noheader,nounits");
        if (procGpu.waitForFinished(500)) {
            QByteArray out = procGpu.readAllStandardOutput().trimmed();
            bool ok = false;
            double val = out.toDouble(&ok);
            if (ok) {
                gpu = val;
            }
        }

        // Query all running GPU processes (graphics & compute) using XML output
        QProcess procVram;
        procVram.start("nvidia-smi", QStringList() << "-q" << "-x");
        if (procVram.waitForFinished(500)) {
            double vramSum = 0;
            QString out = QString::fromUtf8(procVram.readAllStandardOutput());
            
            QRegularExpression blockRx("<process_info>(.*?)</process_info>", QRegularExpression::DotMatchesEverythingOption);
            QRegularExpression pidRx("<pid>(\\d+)</pid>");
            QRegularExpression memRx("<(?:used_memory|used_gpu_memory)>(\\d+)\\s*(MiB|KiB|GiB|B)</(?:used_memory|used_gpu_memory)>");

            QRegularExpressionMatchIterator it = blockRx.globalMatch(out);
            while (it.hasNext()) {
                QRegularExpressionMatch match = it.next();
                QString blockContent = match.captured(1);
                
                QRegularExpressionMatch pidMatch = pidRx.match(blockContent);
                QRegularExpressionMatch memMatch = memRx.match(blockContent);
                if (pidMatch.hasMatch() && memMatch.hasMatch()) {
                    qint64 vpid = pidMatch.captured(1).toLongLong();
                    double memVal = memMatch.captured(1).toDouble();
                    QString unit = memMatch.captured(2);
                    if (unit == "KiB") {
                        memVal /= 1024.0;
                    } else if (unit == "GiB") {
                        memVal *= 1024.0;
                    } else if (unit == "B") {
                        memVal /= (1024.0 * 1024.0);
                    }
                    if (pids.contains(vpid)) {
                        vramSum += memVal; // in MiB
                    }
                }
            }
            vram = vramSum;
        }
        return;
    }

    // Try AMD fallback
    QFile amdGpuBusy("/sys/class/drm/card0/device/gpu_busy_percent");
    if (amdGpuBusy.exists() && amdGpuBusy.open(QIODevice::ReadOnly)) {
        QTextStream stream(&amdGpuBusy);
        gpu = stream.readAll().trimmed().toDouble();
        amdGpuBusy.close();

        QFile amdVram("/sys/class/drm/card0/device/mem_info_vram_used");
        if (amdVram.exists() && amdVram.open(QIODevice::ReadOnly)) {
            QTextStream vramStream(&amdVram);
            vram = vramStream.readAll().trimmed().toDouble() / (1024.0 * 1024.0); // convert B to MB
            amdVram.close();
        }
        return;
    }

    // Fallback if no GPU stats available
    gpu = 0.0;
    vram = 0.0;
}

void StatsWorker::calculateNetUsage(double &net)
{
    qint64 diffBytes = g_networkBytesAccumulator.exchange(0, std::memory_order_relaxed);
    qint64 elapsedMs = m_netTimer.restart();
    if (elapsedMs <= 0) elapsedMs = 1000;

    net = (static_cast<double>(diffBytes) / (1024.0 * 1024.0)) / (elapsedMs / 1000.0);
}
