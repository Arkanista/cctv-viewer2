#include "thumbnailprovider.h"

extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libavutil/imgutils.h>
#include <libavutil/time.h>
#include <libswscale/swscale.h>
}

#include <QDebug>
#include <QPainter>
#include <QDir>
#include <QFileInfo>
#include <QSettings>
#include "hcnetsdk_compat.h"
#include "context.h"
#include "config.h"
#include <thread>
#include <chrono>

static constexpr int THUMBNAIL_WIDTH = 160;
static constexpr int THUMBNAIL_HEIGHT = 90;
static constexpr int FETCH_TIMEOUT_US = 5000000; // 5 seconds

// --------------- ThumbnailFetchWorker ---------------

ThumbnailFetchWorker::ThumbnailFetchWorker(QObject *parent)
    : QObject(parent)
{
}

void ThumbnailFetchWorker::fetchFrame(const QString &rtspUrl, const QString &cacheKey, int timeoutMs)
{
    AVFormatContext *fmtCtx = nullptr;
    AVCodecContext *codecCtx = nullptr;
    AVFrame *frame = nullptr;
    AVFrame *rgbFrame = nullptr;
    SwsContext *swsCtx = nullptr;
    uint8_t *rgbBuffer = nullptr;

    auto cleanup = [&]() {
        if (rgbBuffer) av_free(rgbBuffer);
        if (rgbFrame) av_frame_free(&rgbFrame);
        if (frame) av_frame_free(&frame);
        if (swsCtx) sws_freeContext(swsCtx);
        if (codecCtx) avcodec_free_context(&codecCtx);
        if (fmtCtx) avformat_close_input(&fmtCtx);
    };

    // Set up format context with RTSP options
    fmtCtx = avformat_alloc_context();
    if (!fmtCtx) {
        qWarning() << "[ThumbnailFetch] Failed to allocate format context for" << cacheKey;
        emit fetchFailed(cacheKey);
        return;
    }

    struct InterruptCb {
        int64_t start_time;
        int timeout_ms;
    } icb;
    icb.start_time = av_gettime();
    icb.timeout_ms = timeoutMs; // total fetch timeout

    fmtCtx->interrupt_callback.callback = [](void *ctx) -> int {
        InterruptCb *icb = static_cast<InterruptCb*>(ctx);
        return (av_gettime() - icb->start_time) > (icb->timeout_ms * 1000LL) ? 1 : 0;
    };
    fmtCtx->interrupt_callback.opaque = &icb;

    AVDictionary *opts = nullptr;
    av_dict_set(&opts, "rtsp_transport", "tcp", 0);
    // Limit stimeout to roughly 80% of total timeout or 5s, whichever is larger
    int connTimeoutMs = qMax(5000, timeoutMs * 80 / 100);
    av_dict_set(&opts, "stimeout", QString::number(connTimeoutMs * 1000LL).toUtf8().constData(), 0);
    av_dict_set(&opts, "analyzeduration", "1000000", 0); // 1s analyze
    av_dict_set(&opts, "probesize", "500000", 0); // 500KB probe

    int ret = avformat_open_input(&fmtCtx, rtspUrl.toUtf8().constData(), nullptr, &opts);
    av_dict_free(&opts);

    if (ret < 0) {
        qWarning() << "[ThumbnailFetch] Failed to open" << cacheKey << "error:" << ret;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    // Find stream info (limited duration)
    AVDictionary *streamOpts = nullptr;
    av_dict_set(&streamOpts, "analyzeduration", "1000000", 0);
    ret = avformat_find_stream_info(fmtCtx, nullptr);
    av_dict_free(&streamOpts);

    if (ret < 0) {
        qWarning() << "[ThumbnailFetch] Failed to find stream info for" << cacheKey;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    // Find video stream
    int videoIdx = -1;
    for (unsigned i = 0; i < fmtCtx->nb_streams; ++i) {
        if (fmtCtx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_VIDEO) {
            videoIdx = static_cast<int>(i);
            break;
        }
    }

    if (videoIdx < 0) {
        qWarning() << "[ThumbnailFetch] No video stream found in" << cacheKey;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    // Open codec
    const AVCodecParameters *codecPar = fmtCtx->streams[videoIdx]->codecpar;
#if LIBAVFORMAT_VERSION_MAJOR >= 59
    const AVCodec *codec = avcodec_find_decoder(codecPar->codec_id);
#else
    AVCodec *codec = avcodec_find_decoder(codecPar->codec_id);
#endif
    if (!codec) {
        qWarning() << "[ThumbnailFetch] Decoder not found for" << cacheKey;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    codecCtx = avcodec_alloc_context3(codec);
    if (!codecCtx) {
        qWarning() << "[ThumbnailFetch] Failed to allocate codec context for" << cacheKey;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    avcodec_parameters_to_context(codecCtx, codecPar);
    codecCtx->thread_count = 1; // Minimal threading for thumbnail

    ret = avcodec_open2(codecCtx, codec, nullptr);
    if (ret < 0) {
        qWarning() << "[ThumbnailFetch] Failed to open codec for" << cacheKey;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    // Allocate frames
    frame = av_frame_alloc();
    rgbFrame = av_frame_alloc();
    if (!frame || !rgbFrame) {
        qWarning() << "[ThumbnailFetch] Failed to allocate frames for" << cacheKey;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    // Allocate RGB buffer
    int rgbBufSize = av_image_get_buffer_size(AV_PIX_FMT_RGB32, THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT, 1);
    rgbBuffer = static_cast<uint8_t *>(av_malloc(static_cast<size_t>(rgbBufSize)));
    if (!rgbBuffer) {
        qWarning() << "[ThumbnailFetch] Failed to allocate RGB buffer for" << cacheKey;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    av_image_fill_arrays(rgbFrame->data, rgbFrame->linesize, rgbBuffer,
                         AV_PIX_FMT_RGB32, THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT, 1);

    // Read packets and decode until we get a frame
    AVPacket *pkt = av_packet_alloc();
    bool gotFrame = false;
    int maxPackets = 150; // Safety limit

    while (!gotFrame && maxPackets-- > 0) {
        ret = av_read_frame(fmtCtx, pkt);
        if (ret < 0) break;

        if (pkt->stream_index == videoIdx) {
            ret = avcodec_send_packet(codecCtx, pkt);
            if (ret >= 0) {
                ret = avcodec_receive_frame(codecCtx, frame);
                if (ret == 0) {
                    gotFrame = true;
                }
            }
        }
        av_packet_unref(pkt);
    }
    av_packet_free(&pkt);

    if (!gotFrame) {
        qWarning() << "[ThumbnailFetch] Failed to decode a frame from" << cacheKey;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    // Scale to thumbnail size
    swsCtx = sws_getContext(
        codecCtx->width, codecCtx->height, codecCtx->pix_fmt,
        THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT, AV_PIX_FMT_RGB32,
        SWS_BILINEAR, nullptr, nullptr, nullptr);

    if (!swsCtx) {
        qWarning() << "[ThumbnailFetch] Failed to create scaler for" << cacheKey;
        cleanup();
        emit fetchFailed(cacheKey);
        return;
    }

    sws_scale(swsCtx, frame->data, frame->linesize, 0, codecCtx->height,
              rgbFrame->data, rgbFrame->linesize);

    // Create QImage from the RGB data
    QImage thumbnail(rgbBuffer, THUMBNAIL_WIDTH, THUMBNAIL_HEIGHT,
                     rgbFrame->linesize[0], QImage::Format_RGB32);
    QImage result = thumbnail.copy(); // Deep copy before freeing buffer

    cleanup();

    qInfo() << "[ThumbnailFetch] Successfully fetched thumbnail for" << cacheKey;
    emit frameFetched(cacheKey, result);
}

// --------------- ThumbnailProvider ---------------

ThumbnailProvider::ThumbnailProvider(QObject *parent)
    : QObject(parent)
    , m_fetching(false)
    , m_worker(new ThumbnailFetchWorker)
{
    m_worker->moveToThread(&m_workerThread);

    connect(&m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);
    connect(this, &ThumbnailProvider::startFetch, m_worker, &ThumbnailFetchWorker::fetchFrame);
    connect(m_worker, &ThumbnailFetchWorker::frameFetched, this, &ThumbnailProvider::onFrameFetched);
    connect(m_worker, &ThumbnailFetchWorker::fetchFailed, this, &ThumbnailProvider::onFetchFailed);

    m_workerThread.setObjectName(QStringLiteral("ThumbnailFetcher"));
    m_workerThread.start(QThread::LowPriority);
}

ThumbnailProvider::~ThumbnailProvider()
{
    cancelAll();
    m_workerThread.quit();
    m_workerThread.wait(3000);
}

void ThumbnailProvider::requestThumbnail(const QString &rtspUrl, const QString &cacheKey, int timeoutMs, bool prepend)
{
    QMutexLocker lock(&m_queueMutex);

    // Avoid duplicates in the queue by removing the existing one if we are prepending,
    // or ignoring if we are appending.
    for (int i = 0; i < m_queue.size(); ++i) {
        if (m_queue[i].cacheKey == cacheKey) {
            if (prepend) {
                m_queue.removeAt(i);
                break;
            } else {
                return;
            }
        }
    }

    if (prepend) {
        m_queue.prepend({rtspUrl, cacheKey, timeoutMs});
    } else {
        m_queue.enqueue({rtspUrl, cacheKey, timeoutMs});
    }
    lock.unlock();

    // Trigger processing on the next event loop iteration
    QMetaObject::invokeMethod(this, "processQueue", Qt::QueuedConnection);
}

void ThumbnailProvider::cancelAll()
{
    QMutexLocker lock(&m_queueMutex);
    m_queue.clear();
}

QImage ThumbnailProvider::thumbnail(const QString &cacheKey) const
{
    QMutexLocker lock(&m_cacheMutex);
    return m_cache.value(cacheKey);
}

bool ThumbnailProvider::hasThumbnail(const QString &cacheKey) const
{
    QMutexLocker lock(&m_cacheMutex);
    return m_cache.contains(cacheKey);
}

void ThumbnailProvider::onFrameFetched(const QString &cacheKey, const QImage &image)
{
    {
        QMutexLocker lock(&m_cacheMutex);
        m_cache[cacheKey] = image;
    }

    // Also save it to the filesystem for the QML UI to load
    QString outDir = thumbnailsDir();
    if (!outDir.isEmpty()) {
        QDir().mkpath(outDir);
        QString outPath = QDir(outDir).absoluteFilePath(cacheKey + ".jpg");
        image.save(outPath, "JPEG");
    }

    m_fetching = false;
    emit thumbnailReady(cacheKey);
    processQueue();
}

void ThumbnailProvider::onFetchFailed(const QString &cacheKey)
{
    m_fetching = false;
    emit thumbnailFailed(cacheKey);
    processQueue();
}

void ThumbnailProvider::processQueue()
{
    if (m_fetching) return;

    QMutexLocker lock(&m_queueMutex);
    if (m_queue.isEmpty()) return;

    FetchRequest req = m_queue.dequeue();
    lock.unlock();

    m_fetching = true;
    emit startFetch(req.rtspUrl, req.cacheKey, req.timeoutMs);
}

void ThumbnailProvider::generateSingleThumbnail(const QVariantMap &recorderInfo, int channelId)
{
    QString ip = recorderInfo["ip"].toString();
    QString username = recorderInfo["username"].toString();
    QString password = recorderInfo["password"].toString();

    // Use main stream (01) instead of substream (02) for better quality before downscaling
    QString rtspUrl = QString("rtsp://%1:%2@%3:554/Streaming/Channels/%4%5")
                        .arg(username)
                        .arg(password)
                        .arg(ip)
                        .arg(channelId)
                        .arg("01");
    
    QString cacheKey = QString("%1_%2").arg(ip).arg(channelId);
    
    // Check if the file exists on disk, if so delete it so it's a true refresh
    QString outDir = thumbnailsDir();
    if (!outDir.isEmpty()) {
        QString outPath = QDir(outDir).absoluteFilePath(cacheKey + ".jpg");
        if (QFile::exists(outPath)) {
            QFile::remove(outPath);
        }
    }

    {
        QMutexLocker lock(&m_cacheMutex);
        m_cache.remove(cacheKey);
    }
    
    // Emit ready so the UI updates to show the placeholder immediately
    emit thumbnailReady(cacheKey);

    // 25 second timeout, prepend to queue
    requestThumbnail(rtspUrl, cacheKey, 25000, true);
}

QString ThumbnailProvider::thumbnailsDir() const
{
    QString configPath;
    if (Context::isAuxiliary()) {
        configPath = QSettings().fileName();
    } else if (Context::config()) {
        configPath = Context::config()->fileName();
    } else {
        configPath = QSettings().fileName();
    }

    if (!configPath.isEmpty()) {
        QDir dir(QFileInfo(configPath).absolutePath());
        return dir.absoluteFilePath("thumbnails");
    }
    return QString();
}

void ThumbnailProvider::generateThumbnails(const QVariantMap &recorderInfo)
{
    QString ip = recorderInfo["ip"].toString();
    QString username = recorderInfo["username"].toString();
    QString password = recorderInfo["password"].toString();
    QVariantList cameras = recorderInfo["cameras"].toList();

    QString outDir = thumbnailsDir();
    QDir().mkpath(outDir);

    // Clear old thumbnails for this specific recorder before generating new ones
    QDir dir(outDir);
    QStringList filters;
    filters << QString("%1_*.jpg").arg(ip);
    QFileInfoList oldFiles = dir.entryInfoList(filters, QDir::Files);
    for (const QFileInfo &fi : oldFiles) {
        QFile::remove(fi.absoluteFilePath());
    }

    // Queue new fetches using RTSP
    for (const QVariant &camVar : cameras) {
        QVariantMap cam = camVar.toMap();
        int channelId = cam["channelId"].toInt();
        
        QString rtspUrl = QString("rtsp://%1:%2@%3:554/Streaming/Channels/%4%5")
                            .arg(username)
                            .arg(password)
                            .arg(ip)
                            .arg(channelId)
                            .arg("01");
        
        QString cacheKey = QString("%1_%2").arg(ip).arg(channelId);
        requestThumbnail(rtspUrl, cacheKey);
    }
}

// --------------- ThumbnailImageProvider ---------------

ThumbnailImageProvider::ThumbnailImageProvider(ThumbnailProvider *provider)
    : QQuickImageProvider(QQuickImageProvider::Image)
    , m_provider(provider)
{
}

QImage ThumbnailImageProvider::requestImage(const QString &id, QSize *size, const QSize &requestedSize)
{
    Q_UNUSED(requestedSize)

    QString cleanId = id;
    int queryIdx = cleanId.indexOf('?');
    if (queryIdx >= 0) {
        cleanId = cleanId.left(queryIdx);
    }

    if (m_provider->hasThumbnail(cleanId)) {
        QImage img = m_provider->thumbnail(cleanId);
        if (size) *size = img.size();
        return img;
    }

    // Try loading from disk cache
    QString outDir = m_provider->thumbnailsDir();
    if (!outDir.isEmpty()) {
        QString outPath = QDir(outDir).absoluteFilePath(cleanId + ".jpg");
        if (QFileInfo::exists(outPath)) {
            QImage img(outPath);
            if (!img.isNull()) {
                if (size) *size = img.size();
                return img;
            }
        }
    }

    // Return a dark placeholder
    int w = requestedSize.width() > 0 ? requestedSize.width() : THUMBNAIL_WIDTH;
    int h = requestedSize.height() > 0 ? requestedSize.height() : THUMBNAIL_HEIGHT;

    QImage placeholder(w, h, QImage::Format_RGB32);
    placeholder.fill(QColor(0x15, 0x1c, 0x24));

    // Draw a subtle camera icon in the center
    QPainter painter(&placeholder);
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setPen(Qt::NoPen);

    // Camera body
    QColor iconColor(0x2a, 0x35, 0x40);
    painter.setBrush(iconColor);
    int camW = 20, camH = 14;
    int cx = (w - camW) / 2, cy = (h - camH) / 2;
    painter.drawRoundedRect(cx, cy, camW, camH, 2, 2);

    // Lens circle
    painter.setBrush(QColor(0x0f, 0x15, 0x1b));
    painter.drawEllipse(QPoint(w / 2, h / 2), 4, 4);

    painter.end();

    if (size) *size = placeholder.size();
    return placeholder;
}
