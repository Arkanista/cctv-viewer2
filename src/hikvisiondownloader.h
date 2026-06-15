#ifndef HIKVISIONDOWNLOADER_H
#define HIKVISIONDOWNLOADER_H

#include <QObject>
#include <QVariantMap>
#include <QDateTime>
#include <QTimer>
#include <QProcess>
#include <QList>
#include <QPair>
#include "hcnetsdk_compat.h"

class HikvisionDownloader : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isDownloading READ isDownloading NOTIFY isDownloadingChanged)
    Q_PROPERTY(bool isConverting READ isConverting NOTIFY isConvertingChanged)
    Q_PROPERTY(int progress READ progress NOTIFY progressChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusTextChanged)
    Q_PROPERTY(int overallProgress READ overallProgress NOTIFY overallProgressChanged)

public:
    explicit HikvisionDownloader(QObject *parent = nullptr);
    ~HikvisionDownloader() override;

    bool isDownloading() const;
    bool isConverting() const;
    int progress() const;
    QString statusText() const;
    int overallProgress() const;

    Q_INVOKABLE void startDownload(const QVariantMap &recorderInfo, int channelId, const QDateTime &start, const QDateTime &end, const QString &saveFilePath);
    Q_INVOKABLE void stopDownload();

signals:
    void isDownloadingChanged();
    void isConvertingChanged();
    void progressChanged();
    void statusTextChanged();
    void overallProgressChanged();
    void downloadFinished(bool success, const QString &message);

private slots:
    void checkProgress();
    void onFfmpegFinished(int exitCode, QProcess::ExitStatus exitStatus);

private:
    void startNextSegment();

    bool m_isDownloading;
    bool m_isConverting;
    int m_progress;
    QString m_statusText;
    LONG m_lUserID;
    LONG m_lFileHandle;
    QTimer *m_timer;
    QString m_tempFilePath;
    QString m_finalFilePath;
    QProcess *m_ffmpegProcess;
    qint64 m_lastFileSize = 0;

    struct DownloadSegment {
        QDateTime startTime;
        QDateTime endTime;
        QString tempPath;
        QString finalPath;
    };

    QList<DownloadSegment> m_segments;
    int m_currentSegmentIndex;
    int m_totalSegmentsCount;
    int m_convertedSegmentsCount;

    QVariantMap m_recorderInfo;
    int m_channelId;
    int m_realSdkChannel;
};

#endif // HIKVISIONDOWNLOADER_H
