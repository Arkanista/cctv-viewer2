#ifndef THUMBNAILPROVIDER_H
#define THUMBNAILPROVIDER_H

#include <QObject>
#include <QImage>
#include <QHash>
#include <QQueue>
#include <QMutex>
#include <QThread>
#include <QTimer>
#include <QVariantMap>
#include <QMutex>
#include <QThread>
#include <QTimer>
#include <QQuickImageProvider>

// Forward declarations
struct AVFormatContext;
struct AVCodecContext;
struct AVFrame;
struct SwsContext;

// Worker that runs on a background thread to fetch a single RTSP frame
class ThumbnailFetchWorker : public QObject
{
    Q_OBJECT

public:
    explicit ThumbnailFetchWorker(QObject *parent = nullptr);

public slots:
    void fetchFrame(const QString &rtspUrl, const QString &cacheKey, int timeoutMs);

signals:
    void frameFetched(const QString &cacheKey, const QImage &image);
    void fetchFailed(const QString &cacheKey);
};

// Main provider that orchestrates sequential thumbnail fetching
class ThumbnailProvider : public QObject
{
    Q_OBJECT

public:
    explicit ThumbnailProvider(QObject *parent = nullptr);
    ~ThumbnailProvider() override;

    Q_INVOKABLE void requestThumbnail(const QString &rtspUrl, const QString &cacheKey, int timeoutMs = 8000, bool prepend = false);
    Q_INVOKABLE void cancelAll();
    
    Q_INVOKABLE void generateThumbnails(const QVariantMap &recorderInfo);
    Q_INVOKABLE void generateSingleThumbnail(const QVariantMap &recorderInfo, int channelId);
    Q_INVOKABLE QString thumbnailsDir() const;

    QImage thumbnail(const QString &cacheKey) const;
    bool hasThumbnail(const QString &cacheKey) const;

signals:
    void thumbnailReady(const QString &cacheKey);
    void thumbnailFailed(const QString &cacheKey);

    // Internal signal to dispatch work to the worker thread
    void startFetch(const QString &rtspUrl, const QString &cacheKey, int timeoutMs);

private slots:
    void onFrameFetched(const QString &cacheKey, const QImage &image);
    void onFetchFailed(const QString &cacheKey);
    void processQueue();

private:
    struct FetchRequest {
        QString rtspUrl;
        QString cacheKey;
        int timeoutMs;
    };

    mutable QMutex m_cacheMutex;
    QHash<QString, QImage> m_cache;

    QMutex m_queueMutex;
    QQueue<FetchRequest> m_queue;
    bool m_fetching;

    QThread m_workerThread;
    ThumbnailFetchWorker *m_worker;
};

// QQuickImageProvider to serve cached thumbnails to QML
class ThumbnailImageProvider : public QQuickImageProvider
{
public:
    explicit ThumbnailImageProvider(ThumbnailProvider *provider);

    QImage requestImage(const QString &id, QSize *size, const QSize &requestedSize) override;

private:
    ThumbnailProvider *m_provider;
};

#endif // THUMBNAILPROVIDER_H
