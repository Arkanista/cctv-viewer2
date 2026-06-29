#include "nvrstatusmanager.h"
#include "hikvisionmanager.h"
#include "context.h"
#include <QSettings>
#include <QDebug>
#include <QCoreApplication>
#include <QDateTime>

NvrStatusManager* NvrStatusManager::m_instance = nullptr;

NvrStatusManager::NvrStatusManager(QObject *parent)
    : QObject(parent)
{
    m_instance = this;
    loadSettings();

    // Start 5-minute periodic check timer
    m_timer = new QTimer(this);
    m_timer->setInterval(300000); // 5 minutes (300,000 ms)
    connect(m_timer, &QTimer::timeout, this, &NvrStatusManager::startCheck);

    if (m_monitoringEnabled && hasConfiguredRecorders()) {
        m_timer->start();
    }

    // Run first check after a short delay (e.g., 5 seconds) to allow initial sessions to settle
    QTimer::singleShot(5000, this, [this]() {
        if (m_monitoringEnabled && hasConfiguredRecorders()) {
            startCheck();
        }
    });
}

NvrStatusManager::~NvrStatusManager()
{
    if (m_timer) {
        m_timer->stop();
    }
    m_instance = nullptr;
}

NvrStatusManager* NvrStatusManager::instance()
{
    return m_instance;
}

bool NvrStatusManager::hasConfiguredRecorders() const
{
    if (QCoreApplication::arguments().contains("--simulate-error")) {
        return true;
    }
    QString path = Context::config() ? Context::config()->fileName() : QSettings().fileName();
    QSettings settings(path, QSettings::IniFormat);
    QString jsonStr = settings.value("Hikvision/recordersJson", "[]").toString();
    QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
    return !doc.array().isEmpty();
}

void NvrStatusManager::setMonitoringEnabled(bool val)
{
    if (m_monitoringEnabled != val) {
        m_monitoringEnabled = val;
        emit monitoringEnabledChanged();
        saveSettings();
        onRecordersChanged();
    }
}

void NvrStatusManager::setCheckOffline(bool val)
{
    if (m_checkOffline != val) {
        m_checkOffline = val;
        emit checkOfflineChanged();
        saveSettings();
        startCheck();
    }
}

void NvrStatusManager::setCheckCpu(bool val)
{
    if (m_checkCpu != val) {
        m_checkCpu = val;
        emit checkCpuChanged();
        saveSettings();
        startCheck();
    }
}

void NvrStatusManager::setCheckHw(bool val)
{
    if (m_checkHw != val) {
        m_checkHw = val;
        emit checkHwChanged();
        saveSettings();
        startCheck();
    }
}

void NvrStatusManager::setCheckHdd(bool val)
{
    if (m_checkHdd != val) {
        m_checkHdd = val;
        emit checkHddChanged();
        saveSettings();
        startCheck();
    }
}

void NvrStatusManager::setCheckUnformatted(bool val)
{
    if (m_checkUnformatted != val) {
        m_checkUnformatted = val;
        emit checkUnformattedChanged();
        saveSettings();
        startCheck();
    }
}

void NvrStatusManager::setCheckFull(bool val)
{
    if (m_checkFull != val) {
        m_checkFull = val;
        emit checkFullChanged();
        saveSettings();
        startCheck();
    }
}

void NvrStatusManager::checkNow()
{
    startCheck();
}

void NvrStatusManager::onRecordersChanged()
{
    emit hasConfiguredRecordersChanged();

    if (!hasConfiguredRecorders() || !m_monitoringEnabled) {
        if (m_timer->isActive()) {
            m_timer->stop();
        }
        m_errors.clear();
        emit errorsChanged();
        m_checkedRecorders.clear();
        emit checkedRecordersChanged();
        if (m_hasErrors) {
            m_hasErrors = false;
            emit hasErrorsChanged();
        }
    } else {
        if (!m_timer->isActive()) {
            m_timer->start();
        }
        startCheck();
    }
}

void NvrStatusManager::startCheck()
{
    if (m_isChecking) return;
    if (!m_monitoringEnabled || !hasConfiguredRecorders()) {
        if (m_timer->isActive()) {
            m_timer->stop();
        }
        m_errors.clear();
        emit errorsChanged();
        m_checkedRecorders.clear();
        emit checkedRecordersChanged();
        if (m_hasErrors) {
            m_hasErrors = false;
            emit hasErrorsChanged();
        }
        return;
    }

    m_isChecking = true;
    emit isCheckingChanged();

    // Read latest recorders Json from local config
    QString path = Context::config() ? Context::config()->fileName() : QSettings().fileName();
    QSettings settings(path, QSettings::IniFormat);
    QString jsonStr = settings.value("Hikvision/recordersJson", "[]").toString();
    QJsonDocument doc = QJsonDocument::fromJson(jsonStr.toUtf8());
    QJsonArray recorders = doc.array();

    QVariantMap configs;
    configs["checkOffline"] = m_checkOffline;
    configs["checkCpu"] = m_checkCpu;
    configs["checkHw"] = m_checkHw;
    configs["checkHdd"] = m_checkHdd;
    configs["checkUnformatted"] = m_checkUnformatted;
    configs["checkFull"] = m_checkFull;

    QThread *thread = new QThread();
    NvrStatusWorker *worker = new NvrStatusWorker(recorders, configs);
    worker->moveToThread(thread);

    connect(thread, &QThread::started, worker, &NvrStatusWorker::run);
    connect(worker, &NvrStatusWorker::finished, this, &NvrStatusManager::onCheckFinished);
    connect(worker, &NvrStatusWorker::finished, thread, &QThread::quit);
    connect(worker, &NvrStatusWorker::finished, worker, &QObject::deleteLater);
    connect(thread, &QThread::finished, thread, &QObject::deleteLater);

    thread->start();
}

void NvrStatusManager::onCheckFinished(const QVariantList &errors, const QVariantList &checkedRecorders)
{
    m_isChecking = false;
    emit isCheckingChanged();

    bool errorsChangedFlag = (m_errors != errors);
    m_errors = errors;

    bool checkedChangedFlag = (m_checkedRecorders != checkedRecorders);
    m_checkedRecorders = checkedRecorders;

    bool hadErrors = m_hasErrors;
    m_hasErrors = !m_errors.isEmpty();

    if (errorsChangedFlag) {
        emit errorsChanged();
    }
    if (checkedChangedFlag) {
        emit checkedRecordersChanged();
    }
    if (hadErrors != m_hasErrors) {
        emit hasErrorsChanged();
    }

    qDebug() << "[NvrStatusManager] Checked NVRs. Error count:" << m_errors.size() << "Checked count:" << m_checkedRecorders.size();
}

void NvrStatusManager::loadSettings()
{
    QString path = Context::config() ? Context::config()->fileName() : QSettings().fileName();
    QSettings settings(path, QSettings::IniFormat);
    settings.beginGroup("NvrMonitoring");
    m_monitoringEnabled = settings.value("enabled", true).toBool();
    m_checkOffline = settings.value("checkOffline", true).toBool();
    m_checkCpu = settings.value("checkCpu", true).toBool();
    m_checkHw = settings.value("checkHw", true).toBool();
    m_checkHdd = settings.value("checkHdd", true).toBool();
    m_checkUnformatted = settings.value("checkUnformatted", true).toBool();
    m_checkFull = settings.value("checkFull", true).toBool();
    settings.endGroup();
}

void NvrStatusManager::saveSettings()
{
    QString path = Context::config() ? Context::config()->fileName() : QSettings().fileName();
    QSettings settings(path, QSettings::IniFormat);
    settings.beginGroup("NvrMonitoring");
    settings.setValue("enabled", m_monitoringEnabled);
    settings.setValue("checkOffline", m_checkOffline);
    settings.setValue("checkCpu", m_checkCpu);
    settings.setValue("checkHw", m_checkHw);
    settings.setValue("checkHdd", m_checkHdd);
    settings.setValue("checkUnformatted", m_checkUnformatted);
    settings.setValue("checkFull", m_checkFull);
    settings.endGroup();
}

// ── NvrStatusWorker Implementation ──────────────────────────────────────

NvrStatusWorker::NvrStatusWorker(const QJsonArray &recorders, const QVariantMap &configs, QObject *parent)
    : QObject(parent)
    , m_recorders(recorders)
    , m_configs(configs)
{
}

void NvrStatusWorker::run()
{
    QVariantList errors;
    QVariantList checkedRecorders;
    QString lastCheckTime = QDateTime::currentDateTime().toString("dd.MM.yyyy hh:mm:ss");

    bool simulateError = QCoreApplication::arguments().contains("--simulate-error");
    if (simulateError) {
        if (m_recorders.isEmpty()) {
            // Mockup simulation with no recorders
            QVariantMap mockRec;
            mockRec["name"] = tr("Symulowany Rejestrator");
            mockRec["ip"] = "192.168.1.100";
            mockRec["lastCheck"] = lastCheckTime;
            mockRec["hasError"] = true;

            QVariantList recErrors;
            QVariantMap err1;
            err1["target"] = tr("Dysk 1");
            err1["details"] = tr("Krytyczny błąd/uszkodzenie dysku (Symulacja)");
            recErrors.append(err1);

            QVariantMap err2;
            err2["target"] = "";
            err2["details"] = tr("Brak połączenia lub błąd logowania (Symulacja)");
            recErrors.append(err2);

            mockRec["errors"] = recErrors;
            checkedRecorders.append(mockRec);

            // Add to global errors as well
            QVariantMap gErr1 = err1;
            gErr1["recorderName"] = mockRec["name"];
            gErr1["recorderIp"] = mockRec["ip"];
            gErr1["type"] = "hdd";
            errors.append(gErr1);

            QVariantMap gErr2 = err2;
            gErr2["recorderName"] = mockRec["name"];
            gErr2["recorderIp"] = mockRec["ip"];
            gErr2["type"] = "offline";
            errors.append(gErr2);
        } else {
            // Simulated error on each configured recorder
            for (int i = 0; i < m_recorders.size(); ++i) {
                QJsonObject recorder = m_recorders[i].toObject();
                QString ip = recorder.value("ip").toString();
                QString name = recorder.value("name").toString();
                if (name.isEmpty()) name = ip;

                QVariantMap rec;
                rec["name"] = name;
                rec["ip"] = ip;
                rec["lastCheck"] = lastCheckTime;
                rec["hasError"] = true;

                QVariantList recErrors;
                QVariantMap err1;
                err1["target"] = tr("Dysk 1");
                err1["details"] = tr("Krytyczny błąd/uszkodzenie dysku (Symulacja)");
                recErrors.append(err1);

                QVariantMap err2;
                err2["target"] = "";
                err2["details"] = tr("Brak połączenia lub błąd logowania (Symulacja)");
                recErrors.append(err2);

                rec["errors"] = recErrors;
                checkedRecorders.append(rec);

                QVariantMap gErr1 = err1;
                gErr1["recorderName"] = name;
                gErr1["recorderIp"] = ip;
                gErr1["type"] = "hdd";
                errors.append(gErr1);

                QVariantMap gErr2 = err2;
                gErr2["recorderName"] = name;
                gErr2["recorderIp"] = ip;
                gErr2["type"] = "offline";
                errors.append(gErr2);
            }
        }
        emit finished(errors, checkedRecorders);
        return;
    }

    bool checkOffline = m_configs.value("checkOffline", true).toBool();
    bool checkCpu = m_configs.value("checkCpu", true).toBool();
    bool checkHw = m_configs.value("checkHw", true).toBool();
    bool checkHdd = m_configs.value("checkHdd", true).toBool();
    bool checkUnformatted = m_configs.value("checkUnformatted", true).toBool();
    bool checkFull = m_configs.value("checkFull", true).toBool();

    for (int i = 0; i < m_recorders.size(); ++i) {
        QJsonObject recorder = m_recorders[i].toObject();
        QString ip = recorder.value("ip").toString();
        int port = recorder.value("port").toInt(8000);
        QString username = recorder.value("username").toString();
        QString password = recorder.value("password").toString();
        QString name = recorder.value("name").toString();
        if (name.isEmpty()) name = ip;

        QVariantMap rec;
        rec["name"] = name;
        rec["ip"] = ip;
        rec["lastCheck"] = lastCheckTime;
        rec["hasError"] = false;
        QVariantList recErrors;

        // Try to fetch existing connection session, or open a new cached session
        LONG lUserID = HikvisionManager::instance()->getSession(ip, port, username, password);
        if (lUserID < 0) {
            if (checkOffline) {
                QVariantMap err;
                err["recorderName"] = name;
                err["recorderIp"] = ip;
                err["type"] = "offline";
                err["target"] = "";
                err["details"] = tr("Brak połączenia lub błąd logowania");
                errors.append(err);

                QVariantMap localErr;
                localErr["target"] = "";
                localErr["details"] = err["details"];
                recErrors.append(localErr);
            }
            rec["hasError"] = !recErrors.isEmpty();
            rec["errors"] = recErrors;
            checkedRecorders.append(rec);
            continue;
        }

        // Query status
        NET_DVR_WORKSTATE_V30 workState;
        std::memset(&workState, 0, sizeof(NET_DVR_WORKSTATE_V30));
        BOOL ret = NET_DVR_GetDVRWorkState_V30(lUserID, &workState);
        if (!ret) {
            if (checkOffline) {
                QVariantMap err;
                err["recorderName"] = name;
                err["recorderIp"] = ip;
                err["type"] = "offline";
                err["target"] = "";
                err["details"] = tr("Błąd odczytu stanu rejestratora (SDK)");
                errors.append(err);

                QVariantMap localErr;
                localErr["target"] = "";
                localErr["details"] = err["details"];
                recErrors.append(localErr);
            }
            rec["hasError"] = !recErrors.isEmpty();
            rec["errors"] = recErrors;
            checkedRecorders.append(rec);
            continue;
        }

        // Check Device CPU Overload
        if (checkCpu && workState.dwDeviceStatic == 1) {
            QVariantMap err;
            err["recorderName"] = name;
            err["recorderIp"] = ip;
            err["type"] = "cpu";
            err["target"] = "";
            err["details"] = tr("Wysokie obciążenie procesora (>85%)");
            errors.append(err);

            QVariantMap localErr;
            localErr["target"] = "";
            localErr["details"] = err["details"];
            recErrors.append(localErr);
        }

        // Check Device Hardware Error
        if (checkHw && workState.dwDeviceStatic == 2) {
            QVariantMap err;
            err["recorderName"] = name;
            err["recorderIp"] = ip;
            err["type"] = "hw";
            err["target"] = "";
            err["details"] = tr("Błąd sprzętowy urządzenia");
            errors.append(err);

            QVariantMap localErr;
            localErr["target"] = "";
            localErr["details"] = err["details"];
            recErrors.append(localErr);
        }

        // Check Hard Disks
        for (int d = 0; d < MAX_DISKNUM_V30; ++d) {
            NET_DVR_DISKSTATE disk = workState.struHardDiskStatic[d];
            if (disk.dwVolume > 0) {
                QString diskLabel = tr("Dysk %1").arg(d + 1);

                // Disk abnormal/sleep error/can't connect/other exception
                if (checkHdd && (disk.dwHardDiskStatic == 2 || disk.dwHardDiskStatic == 3 || disk.dwHardDiskStatic == 5 || disk.dwHardDiskStatic == 8)) {
                    QVariantMap err;
                    err["recorderName"] = name;
                    err["recorderIp"] = ip;
                    err["type"] = "hdd";
                    err["target"] = diskLabel;
                    err["details"] = tr("Krytyczny błąd/uszkodzenie dysku");
                    errors.append(err);

                    QVariantMap localErr;
                    localErr["target"] = diskLabel;
                    localErr["details"] = err["details"];
                    recErrors.append(localErr);
                }
                // Disk unformatted
                else if (checkUnformatted && disk.dwHardDiskStatic == 4) {
                    QVariantMap err;
                    err["recorderName"] = name;
                    err["recorderIp"] = ip;
                    err["type"] = "unformatted";
                    err["target"] = diskLabel;
                    err["details"] = tr("Dysk niesformatowany");
                    errors.append(err);

                    QVariantMap localErr;
                    localErr["target"] = diskLabel;
                    localErr["details"] = err["details"];
                    recErrors.append(localErr);
                }
                // Disk full (non-looping coverage)
                else if (checkFull && disk.dwHardDiskStatic == 7) {
                    QVariantMap err;
                    err["recorderName"] = name;
                    err["recorderIp"] = ip;
                    err["type"] = "full";
                    err["target"] = diskLabel;
                    err["details"] = tr("Dysk pełny (nadpisywanie wyłączone)");
                    errors.append(err);

                    QVariantMap localErr;
                    localErr["target"] = diskLabel;
                    localErr["details"] = err["details"];
                    recErrors.append(localErr);
                }
            }
        }

        rec["hasError"] = !recErrors.isEmpty();
        rec["errors"] = recErrors;
        checkedRecorders.append(rec);
    }

    emit finished(errors, checkedRecorders);
}
