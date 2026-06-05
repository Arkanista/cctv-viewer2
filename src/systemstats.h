#ifndef SYSTEMSTATS_H
#define SYSTEMSTATS_H

#include <QObject>
#include <QTimer>
#include <QVector>
#include <QHash>
#include <atomic>
#include <QElapsedTimer>
#include <QThread>

class StatsWorker : public QObject
{
    Q_OBJECT
public:
    explicit StatsWorker(QObject *parent = nullptr);
    ~StatsWorker() override = default;

public slots:
    void doWork();

signals:
    void workDone(double cpu, double gpu, double ram, double vram, double net);

private:
    QVector<qint64> getProgramPids();
    void calculateCpuAndRam(const QVector<qint64> &pids, double &cpu, double &ram);
    void calculateGpuAndVram(const QVector<qint64> &pids, double &gpu, double &vram);
    void calculateNetUsage(double &net);

    qint64 m_prevTotalCpuTime = 0;
    QHash<qint64, qint64> m_prevProcessCpuTimes;
    QElapsedTimer m_netTimer;
};

class SystemStats : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double cpuUsage READ cpuUsage NOTIFY statsChanged)
    Q_PROPERTY(double gpuUsage READ gpuUsage NOTIFY statsChanged)
    Q_PROPERTY(double ramUsage READ ramUsage NOTIFY statsChanged)
    Q_PROPERTY(double vramUsage READ vramUsage NOTIFY statsChanged)
    Q_PROPERTY(double netUsage READ netUsage NOTIFY statsChanged)

public:
    explicit SystemStats(QObject *parent = nullptr);
    ~SystemStats() override;

    double cpuUsage() const { return m_cpuUsage; }
    double gpuUsage() const { return m_gpuUsage; }
    double ramUsage() const { return m_ramUsage; }
    double vramUsage() const { return m_vramUsage; }
    double netUsage() const { return m_netUsage; }

signals:
    void statsChanged();

private slots:
    void onWorkDone(double cpu, double gpu, double ram, double vram, double net);

private:
    double m_cpuUsage = 0.0;
    double m_gpuUsage = 0.0;
    double m_ramUsage = 0.0;
    double m_vramUsage = 0.0;
    double m_netUsage = 0.0;

    QTimer *m_timer;
    QThread *m_workerThread;
    StatsWorker *m_worker;
};

#endif // SYSTEMSTATS_H
