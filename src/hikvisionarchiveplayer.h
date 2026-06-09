#ifndef HIKVISIONARCHIVEPLAYER_H
#define HIKVISIONARCHIVEPLAYER_H

#include <QQuickPaintedItem>
#include <QImage>
#include <QDateTime>
#include <QPointer>
#include <mutex>
#include <atomic>
#include <memory>
#include <vector>
#include <chrono>
#include <condition_variable>
#include <thread>
#include "hcnetsdk_compat.h"



class HikvisionArchivePlayer : public QQuickPaintedItem
{
    Q_OBJECT
    Q_PROPERTY(QString recorderIp READ recorderIp WRITE setRecorderIp NOTIFY recorderIpChanged)
    Q_PROPERTY(int channelId READ channelId WRITE setChannelId NOTIFY channelIdChanged)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(QString username READ username WRITE setUsername NOTIFY usernameChanged)
    Q_PROPERTY(QString password READ password WRITE setPassword NOTIFY passwordChanged)
    Q_PROPERTY(qint64 currentPlayheadMs READ currentPlayheadMs NOTIFY playheadChanged)
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY playingChanged)
    Q_PROPERTY(int videoWidth READ videoWidth NOTIFY videoSizeChanged)
    Q_PROPERTY(int videoHeight READ videoHeight NOTIFY videoSizeChanged)

public:
    explicit HikvisionArchivePlayer(QQuickItem *parent = nullptr);
    ~HikvisionArchivePlayer();

    void paint(QPainter *painter) override;

    QString recorderIp() const;
    void setRecorderIp(const QString &ip);

    int channelId() const;
    void setChannelId(int id);
    
    int port() const;
    void setPort(int port);

    QString username() const;
    void setUsername(const QString &username);

    QString password() const;
    void setPassword(const QString &password);

    qint64 currentPlayheadMs() const;
    bool isPlaying() const;
    int videoWidth() const;
    int videoHeight() const;

    Q_INVOKABLE void playAtTime(const QDateTime &dateTime);
    Q_INVOKABLE void setPlaybackSpeed(int speedMultiplier); // 1, 2, 4, 8, -1, -2, -4, -8
    Q_INVOKABLE void pause();
    Q_INVOKABLE void resume();
    Q_INVOKABLE void stop();
    Q_INVOKABLE bool hasActiveStream() const;
    Q_INVOKABLE bool hasReceivedFrames() const;
    Q_INVOKABLE bool saveCurrentFrame(const QString &path) const;


signals:
    void recorderIpChanged();
    void channelIdChanged();
    void portChanged();
    void usernameChanged();
    void passwordChanged();
    void playheadChanged();
    void playingChanged();
    void videoSizeChanged();

private:
    void updateImage(const QImage &img);
    static void PlayDataCallBack(LONG lPlayHandle, DWORD dwDataType, BYTE *pBuffer, DWORD dwBufSize, void *pUser);
    static void DisplayCallBack(long nPort, char *pBuf, long nSize, long nWidth, long nHeight, long nStamp, long nType, long nReserved);

    void cleanupPlayback();
    bool ensureLogin();

    QString m_recorderIp;
    int m_channelId = 1;
    int m_port = 8000;
    QString m_username;
    QString m_password;

    LONG m_lUserID = -1;
    std::atomic<LONG> m_lPlayHandle{-1};
    std::atomic<LONG> m_nPort{-1};
    DWORD m_realSdkChannel = 1;

    bool m_isPlaying = false;
    qint64 m_currentPlayheadMs = 0;

    QImage m_currentImage;
    mutable std::mutex m_imageMutex;



public:
    struct FrameBuffer {
        std::vector<unsigned char> yv12Data;
        std::vector<unsigned char> rgbData;
        int width = 0;
        int height = 0;
        std::atomic<bool> inUse{false};
    };

private:
    std::shared_ptr<FrameBuffer> getOrCreateFrameBuffer(int width, int height);

    std::vector<std::shared_ptr<FrameBuffer>> m_frameBufferPool;
    std::mutex m_poolMutex;

    std::atomic<bool> m_sysHeadReceived{false};
    std::atomic<int> m_playbackSpeed{1};
    std::atomic<int> m_currentNvrSpeed{1};
    void applyPlaybackSpeed();

    std::atomic<bool> m_pacingInitialized{false};
    std::chrono::steady_clock::time_point m_pacingStartTime;
    std::atomic<long> m_pacingStartStamp{0};
    std::atomic<bool> m_stopPacing{false};
    std::atomic<int> m_activeDisplayCallbacks{0};

    std::atomic<long> m_lastStamp{0};
    std::chrono::steady_clock::time_point m_lastFrameRealTime;
    std::atomic<int> m_zeroStampCount{0};

    struct QueueFrame {
        std::vector<unsigned char> yv12Data;
        int width = 0;
        int height = 0;
        long stamp = 0;
    };
    std::vector<QueueFrame> m_frameQueue;
    std::mutex m_queueMutex;
    std::condition_variable m_queueCond;
    std::thread m_presentationThread;
    std::atomic<bool> m_runPresentation{false};
    void presentationLoop();
};

#endif // HIKVISIONARCHIVEPLAYER_H
