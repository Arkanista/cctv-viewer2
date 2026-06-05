#ifndef HIKVISIONDOWNLOADER_H
#define HIKVISIONDOWNLOADER_H

#include <QObject>
#include <QVariantMap>
#include <QDateTime>
#include <QTimer>
#include <QProcess>
#include "hcnetsdk_compat.h"

class HikvisionDownloader : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isDownloading READ isDownloading NOTIFY isDownloadingChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)

public:
    explicit HikvisionDownloader(QObject *parent = nullptr);
    ~HikvisionDownloader() override;

    bool isDownloading() const;
    int progress() const;

    Q_INVOKABLE void startDownload(const QVariantMap &recorderInfo, int channelId, const QDateTime &start, const QDateTime &end, const QString &saveFilePath);
    Q_INVOKABLE void stopDownload();

signals:
    void isDownloadingChanged();
    void progressChanged();
    void downloadFinished(bool success, const QString &message);

private slots:
    void checkProgress();
    void onFfmpegFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    bool m_isDownloading;
    int m_progress;
    LONG m_lUserID;
    LONG m_lFileHandle;
    QTimer *m_timer;
    QString m_tempFilePath;
    QString m_finalFilePath;
    QProcess *m_ffmpegProcess;
    qint64 m_lastFileSize = 0;
};

#endif // HIKVISIONDOWNLOADER_H
