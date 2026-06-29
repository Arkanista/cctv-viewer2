#ifndef NVRSTATUSMANAGER_H
#define NVRSTATUSMANAGER_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QTimer>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QThread>

class NvrStatusManager : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool hasErrors READ hasErrors NOTIFY hasErrorsChanged)
    Q_PROPERTY(QVariantList errors READ errors NOTIFY errorsChanged)
    Q_PROPERTY(bool isChecking READ isChecking NOTIFY isCheckingChanged)
    Q_PROPERTY(QVariantList checkedRecorders READ checkedRecorders NOTIFY checkedRecordersChanged)

    Q_PROPERTY(bool monitoringEnabled READ monitoringEnabled WRITE setMonitoringEnabled NOTIFY monitoringEnabledChanged)
    Q_PROPERTY(bool hasConfiguredRecorders READ hasConfiguredRecorders NOTIFY hasConfiguredRecordersChanged)

    Q_PROPERTY(bool checkOffline READ checkOffline WRITE setCheckOffline NOTIFY checkOfflineChanged)
    Q_PROPERTY(bool checkCpu READ checkCpu WRITE setCheckCpu NOTIFY checkCpuChanged)
    Q_PROPERTY(bool checkHw READ checkHw WRITE setCheckHw NOTIFY checkHwChanged)
    Q_PROPERTY(bool checkHdd READ checkHdd WRITE setCheckHdd NOTIFY checkHddChanged)
    Q_PROPERTY(bool checkUnformatted READ checkUnformatted WRITE setCheckUnformatted NOTIFY checkUnformattedChanged)
    Q_PROPERTY(bool checkFull READ checkFull WRITE setCheckFull NOTIFY checkFullChanged)

public:
    explicit NvrStatusManager(QObject *parent = nullptr);
    virtual ~NvrStatusManager() override;

    static NvrStatusManager* instance();

    bool hasErrors() const { return m_hasErrors; }
    QVariantList errors() const { return m_errors; }
    bool isChecking() const { return m_isChecking; }
    QVariantList checkedRecorders() const { return m_checkedRecorders; }

    bool monitoringEnabled() const { return m_monitoringEnabled; }
    bool hasConfiguredRecorders() const;

    bool checkOffline() const { return m_checkOffline; }
    bool checkCpu() const { return m_checkCpu; }
    bool checkHw() const { return m_checkHw; }
    bool checkHdd() const { return m_checkHdd; }
    bool checkUnformatted() const { return m_checkUnformatted; }
    bool checkFull() const { return m_checkFull; }

    void setMonitoringEnabled(bool val);

    void setCheckOffline(bool val);
    void setCheckCpu(bool val);
    void setCheckHw(bool val);
    void setCheckHdd(bool val);
    void setCheckUnformatted(bool val);
    void setCheckFull(bool val);

    Q_INVOKABLE void checkNow();
    Q_INVOKABLE void onRecordersChanged();

signals:
    void hasErrorsChanged();
    void errorsChanged();
    void isCheckingChanged();
    void checkedRecordersChanged();

    void monitoringEnabledChanged();
    void hasConfiguredRecordersChanged();

    void checkOfflineChanged();
    void checkCpuChanged();
    void checkHwChanged();
    void checkHddChanged();
    void checkUnformattedChanged();
    void checkFullChanged();

private slots:
    void onCheckFinished(const QVariantList &errors, const QVariantList &checkedRecorders);

private:
    void startCheck();
    void loadSettings();
    void saveSettings();

    static NvrStatusManager *m_instance;
    QTimer *m_timer;
    bool m_hasErrors = false;
    QVariantList m_errors;
    QVariantList m_checkedRecorders;
    bool m_isChecking = false;

    bool m_monitoringEnabled = true;

    bool m_checkOffline = true;
    bool m_checkCpu = true;
    bool m_checkHw = true;
    bool m_checkHdd = true;
    bool m_checkUnformatted = true;
    bool m_checkFull = true;
};

class NvrStatusWorker : public QObject
{
    Q_OBJECT
public:
    NvrStatusWorker(const QJsonArray &recorders, const QVariantMap &configs, QObject *parent = nullptr);
    virtual ~NvrStatusWorker() override = default;

signals:
    void finished(const QVariantList &errors, const QVariantList &checkedRecorders);

public slots:
    void run();

private:
    QJsonArray m_recorders;
    QVariantMap m_configs;
};

#endif // NVRSTATUSMANAGER_H
