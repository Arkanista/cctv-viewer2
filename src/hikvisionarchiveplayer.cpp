#include "hikvisionarchiveplayer.h"
#ifdef __linux__
#include <malloc.h>
#endif
#include "hikvisionmanager.h"
#include "qmlav/src/qmlavdemuxer.h"
#include <QPainter>
#include <QDebug>
#include <QCoreApplication>
#include <QThreadPool>
#include <QRunnable>
#include <iostream>
#include <set>
#include <QAudioDeviceInfo>

// Hikvision PlayM4 decoder constants (usually YV12)
#define T_YV12 3
#define T_AUDIO16 101
#define T_AUDIO8 100

static QByteArray resampleAudio(const char* inputBuf, int inputSize, int inputRate, int outputRate, int outputChannels)
{
    // Sane limits to prevent crash or massive allocations on corrupted/unexpected audio data
    if (inputSize <= 0 || inputSize > 1024 * 1024 || inputRate < 4000 || inputRate > 192000 
        || outputRate < 4000 || outputRate > 192000 || outputChannels <= 0 || outputChannels > 8) {
        return QByteArray();
    }

    const int16_t* inputSamples = reinterpret_cast<const int16_t*>(inputBuf);
    int inputSamplesCount = inputSize / 2;
    if (inputSamplesCount <= 0) {
        return QByteArray();
    }

    // Jeśli formaty są identyczne i wyjście to Mono, po prostu kopiujemy dane
    if (inputRate == outputRate && outputChannels == 1) {
        return QByteArray(inputBuf, inputSize);
    }

    int outputSamplesCount = static_cast<int>(static_cast<double>(inputSamplesCount) * outputRate / inputRate);
    if (outputSamplesCount <= 0) {
        return QByteArray();
    }

    QByteArray outputBuf;
    outputBuf.resize(outputSamplesCount * outputChannels * 2);
    int16_t* outputSamples = reinterpret_cast<int16_t*>(outputBuf.data());

    double ratio = static_cast<double>(inputRate) / outputRate;

    for (int i = 0; i < outputSamplesCount; ++i) {
        double srcIndex = i * ratio;
        int srcIndexFloor = static_cast<int>(srcIndex);
        double fraction = srcIndex - srcIndexFloor;

        int16_t sample = 0;
        if (srcIndexFloor >= inputSamplesCount - 1) {
            sample = inputSamples[inputSamplesCount - 1];
        } else {
            int16_t s1 = inputSamples[srcIndexFloor];
            int16_t s2 = inputSamples[srcIndexFloor + 1];
            sample = static_cast<int16_t>((1.0 - fraction) * s1 + fraction * s2);
        }

        for (int ch = 0; ch < outputChannels; ++ch) {
            outputSamples[i * outputChannels + ch] = sample;
        }
    }

    return outputBuf;
}

class YV12ToRGBTask : public QRunnable
{
public:
    YV12ToRGBTask(QPointer<HikvisionArchivePlayer> player, std::shared_ptr<HikvisionArchivePlayer::FrameBuffer> frame, uint64_t sessionId)
        : m_player(player), m_frame(frame), m_taskSessionId(sessionId)
    {
        setAutoDelete(true);
    }

    void run() override
    {
        if (!m_player) {
            return;
        }
        if (!m_frame) {
            m_player->m_pendingTasks--;
            return;
        }

        // Check if session has changed before starting expensive RGB conversion
        if (m_player->m_playbackSessionId.load() != m_taskSessionId) {
            m_frame->inUse = false;
            m_player->m_pendingTasks--;
            return;
        }

        int width = m_frame->width;
        int height = m_frame->height;

        if (width <= 0 || height <= 0) {
            m_frame->inUse = false;
            m_player->m_pendingTasks--;
            return;
        }

        const unsigned char* yPlane = m_frame->yv12Data.data();
        const unsigned char* vPlane = yPlane + width * height;
        const unsigned char* uPlane = vPlane + (width * height) / 4;

        unsigned char* destData = m_frame->rgbData.data();
        int destStride = width * 4;
        int halfWidth = width / 2;

        for (int y = 0; y < height; y++) {
            QRgb* scanLine = reinterpret_cast<QRgb*>(destData + (y * destStride));
            const unsigned char* yRow = yPlane + (y * width);
            const unsigned char* uRow = uPlane + ((y / 2) * halfWidth);
            const unsigned char* vRow = vPlane + ((y / 2) * halfWidth);

            for (int x = 0; x < width; x += 2) {
                int uv_x = x >> 1;
                int U = uRow[uv_x] - 128;
                int V = vRow[uv_x] - 128;

                int r_diff = V + (V >> 2) + (V >> 3) + (V >> 5);
                int g_diff = - ((U >> 2) + (U >> 4) + (U >> 5)) - ((V >> 1) + (V >> 3) + (V >> 4) + (V >> 5));
                int b_diff = U + (U >> 1) + (U >> 2) + (U >> 6);

                // Pixel 1 (x)
                {
                    int Y = yRow[x];
                    int r = Y + r_diff;
                    int g = Y + g_diff;
                    int b = Y + b_diff;

                    r = std::min(255, std::max(0, r));
                    g = std::min(255, std::max(0, g));
                    b = std::min(255, std::max(0, b));

                    scanLine[x] = (0xff000000 | (r << 16) | (g << 8) | b);
                }

                // Pixel 2 (x + 1)
                {
                    int Y = yRow[x + 1];
                    int r = Y + r_diff;
                    int g = Y + g_diff;
                    int b = Y + b_diff;

                    r = std::min(255, std::max(0, r));
                    g = std::min(255, std::max(0, g));
                    b = std::min(255, std::max(0, b));

                    scanLine[x + 1] = (0xff000000 | (r << 16) | (g << 8) | b);
                }
            }
        }

        if (!m_player || m_player->m_playbackSessionId.load() != m_taskSessionId) {
            m_frame->inUse = false;
            if (m_player) {
                m_player->m_pendingTasks--;
            }
            return;
        }

        // Wrap RGB buffer in a QImage
        auto* pShared = new std::shared_ptr<HikvisionArchivePlayer::FrameBuffer>(m_frame);
        QImage img(m_frame->rgbData.data(), width, height, destStride, QImage::Format_RGB32, [](void* info) {
            auto* pShared = static_cast<std::shared_ptr<HikvisionArchivePlayer::FrameBuffer>*>(info);
            if (pShared) {
                (*pShared)->inUse = false;
                delete pShared;
            }
        }, pShared);

        QPointer<HikvisionArchivePlayer> pPlayer = m_player;
        if (pPlayer) {
            pPlayer->m_guiPendingTasks++;
            QMetaObject::invokeMethod(pPlayer.data(), [pPlayer, img, sessionId = m_taskSessionId]() {
                if (pPlayer) {
                    if (pPlayer->m_playbackSessionId.load() == sessionId) {
                        pPlayer->updateImage(img);
                    }
                    pPlayer->m_guiPendingTasks--;
                }
            }, Qt::QueuedConnection);
            pPlayer->m_pendingTasks--;
        }
    }

private:
    QPointer<HikvisionArchivePlayer> m_player;
    std::shared_ptr<HikvisionArchivePlayer::FrameBuffer> m_frame;
    uint64_t m_taskSessionId;
};

static std::mutex s_activePlayersMutex;
static std::set<HikvisionArchivePlayer*> s_activePlayers;

HikvisionArchivePlayer::HikvisionArchivePlayer(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    {
        std::lock_guard<std::mutex> lock(s_activePlayersMutex);
        s_activePlayers.insert(this);
    }
    m_currentSpeedMultiplier = 1;

    m_workerThread = new QThread(this);
    m_worker = new QObject();
    m_worker->moveToThread(m_workerThread);
    m_workerThread->start();

    // The Hikvision SDK (HCNetSDK) requires NET_DVR_Init(). 
    // HikvisionManager already calls it.
    qDebug() << "[HikArchive] Component created";
}

HikvisionArchivePlayer::~HikvisionArchivePlayer()
{
    qDebug() << "[HikArchive] ~HikvisionArchivePlayer() DESTRUCTOR CALLED!";
    
    if (m_workerThread) {
        m_workerThread->quit();
        m_workerThread->wait();
    }

    cleanupPlayback();

    // Wait for all background YV12ToRGBTask tasks to complete
    int waitCount = 0;
    while (m_pendingTasks.load() > 0 && waitCount < 1000) { // max 5000ms safeguard
        QThread::msleep(5);
        waitCount++;
    }
    if (m_pendingTasks.load() > 0) {
        qWarning() << "[HikArchive] Destructor timed out waiting for pending tasks:" << m_pendingTasks.load();
    }
    
    {
        std::lock_guard<std::mutex> lock(s_activePlayersMutex);
        s_activePlayers.erase(this);
    }

    if (m_lUserID >= 0) {
        if (HikvisionManager::instance()) {
            HikvisionManager::instance()->logoutShared(m_recorderIp);
        } else {
            NET_DVR_Logout(m_lUserID);
        }
        m_lUserID = -1;
    }

    if (m_worker) {
        delete m_worker;
        m_worker = nullptr;
    }
    if (m_workerThread) {
        delete m_workerThread;
        m_workerThread = nullptr;
    }

#ifdef __linux__
    malloc_trim(0);
#endif
}

std::mutex s_portMapMutex;
static std::map<LONG, HikvisionArchivePlayer*> s_portMap;

void HikvisionArchivePlayer::cleanupPlayback()
{
    m_playbackSessionId++;
    LONG playHandle = -1;
    LONG port = -1;
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        playHandle = m_lPlayHandle.exchange(-1);
        port = m_nPort.exchange(-1);
    }

    m_lastAudioStamp = 0;
    m_lastProposedSampleRate = 0;
    m_sampleRateConsecutiveCount = 0;

    qDebug() << "[HikArchive] cleanupPlayback: playHandle=" << playHandle << "port=" << port << "m_lUserID=" << m_lUserID;

    if (playHandle >= 0) {
        if (!NET_DVR_StopPlayBack(playHandle)) {
            qWarning() << "[HikArchive] NET_DVR_StopPlayBack FAILED. Error:" << NET_DVR_GetLastError();
        } else {
            qDebug() << "[HikArchive] NET_DVR_StopPlayBack OK";
        }
    }

    // Clean up standard QAudioOutput safely and asynchronously on the GUI thread
    if (QThread::currentThread() != qApp->thread()) {
        QMetaObject::invokeMethod(this, [this]() {
            std::lock_guard<std::mutex> lock(m_audioMutex);
            if (m_audioOutput) {
                m_audioOutput->stop();
                m_audioOutput->deleteLater();
                m_audioOutput = nullptr;
            }
            m_audioOutputDevice = nullptr;
        }, Qt::QueuedConnection);
    } else {
        std::lock_guard<std::mutex> lock(m_audioMutex);
        if (m_audioOutput) {
            m_audioOutput->stop();
            m_audioOutput->deleteLater();
            m_audioOutput = nullptr;
        }
        m_audioOutputDevice = nullptr;
    }

    if (port >= 0) {
        PlayM4_StopSoundShare(port); // Port-specific stopping instead of global PlayM4_StopSound()
        m_soundPlaying = false;
        {
            std::lock_guard<std::mutex> lock(s_portMapMutex);
            s_portMap.erase(port);
        }
        if (!PlayM4_Stop(port)) {
            qWarning() << "[HikArchive] PlayM4_Stop FAILED. Error:" << PlayM4_GetLastError(port);
        } else {
            qDebug() << "[HikArchive] PlayM4_Stop OK";
        }
        if (!PlayM4_CloseStream(port)) {
            qWarning() << "[HikArchive] PlayM4_CloseStream FAILED. Error:" << PlayM4_GetLastError(port);
        } else {
            qDebug() << "[HikArchive] PlayM4_CloseStream OK";
        }
        if (!PlayM4_FreePort(port)) {
            qWarning() << "[HikArchive] PlayM4_FreePort FAILED. Error:" << PlayM4_GetLastError(port);
        } else {
            qDebug() << "[HikArchive] PlayM4_FreePort OK";
        }
    }
    
    {
        std::lock_guard<std::mutex> lock(m_imageMutex);
        m_currentImage = QImage();
    }
    
    if (QThread::currentThread() != qApp->thread()) {
        QMetaObject::invokeMethod(this, [this]() {
            update();
            emit playingChanged();
        }, Qt::QueuedConnection);
    } else {
        update();
        emit playingChanged();
    }

    {
        std::lock_guard<std::mutex> lock(m_poolMutex);
        m_frameBufferPool.clear();
    }

    m_isPlaying = false;

    if (m_fps != 0) {
        m_fps = 0;
        m_fpsCounter = 0;
        m_lastFpsTime = 0;
        if (QThread::currentThread() != qApp->thread()) {
            QMetaObject::invokeMethod(this, [this]() {
                emit fpsChanged();
            }, Qt::QueuedConnection);
        } else {
            emit fpsChanged();
        }
    }
}

QString HikvisionArchivePlayer::recorderIp() const { return m_recorderIp; }
void HikvisionArchivePlayer::setRecorderIp(const QString &ip) {
    if (m_recorderIp != ip) {
        QString oldIp = m_recorderIp;
        LONG oldUserId = m_lUserID.exchange(-1);
        m_recorderIp = ip;
        emit recorderIpChanged();

        QMetaObject::invokeMethod(m_worker, [this, oldIp, oldUserId]() {
            cleanupPlayback();
            if (oldUserId >= 0) {
                if (HikvisionManager::instance()) {
                    HikvisionManager::instance()->logoutShared(oldIp);
                } else {
                    NET_DVR_Logout(oldUserId);
                }
            }
        }, Qt::QueuedConnection);
    }
}

int HikvisionArchivePlayer::channelId() const { return m_channelId; }
void HikvisionArchivePlayer::setChannelId(int id) {
    if (m_channelId != id) {
        m_channelId = id;
        emit channelIdChanged();

        QMetaObject::invokeMethod(m_worker, [this]() {
            cleanupPlayback();
        }, Qt::QueuedConnection);
    }
}

int HikvisionArchivePlayer::port() const { return m_port; }
void HikvisionArchivePlayer::setPort(int p) {
    if (m_port != p) {
        QString oldIp = m_recorderIp;
        LONG oldUserId = m_lUserID.exchange(-1);
        m_port = p;
        emit portChanged();

        QMetaObject::invokeMethod(m_worker, [this, oldIp, oldUserId]() {
            cleanupPlayback();
            if (oldUserId >= 0) {
                if (HikvisionManager::instance()) {
                    HikvisionManager::instance()->logoutShared(oldIp);
                } else {
                    NET_DVR_Logout(oldUserId);
                }
            }
        }, Qt::QueuedConnection);
    }
}

QString HikvisionArchivePlayer::username() const { return m_username; }
void HikvisionArchivePlayer::setUsername(const QString &un) {
    if (m_username != un) {
        QString oldIp = m_recorderIp;
        LONG oldUserId = m_lUserID.exchange(-1);
        m_username = un;
        emit usernameChanged();

        QMetaObject::invokeMethod(m_worker, [this, oldIp, oldUserId]() {
            cleanupPlayback();
            if (oldUserId >= 0) {
                if (HikvisionManager::instance()) {
                    HikvisionManager::instance()->logoutShared(oldIp);
                } else {
                    NET_DVR_Logout(oldUserId);
                }
            }
        }, Qt::QueuedConnection);
    }
}

QString HikvisionArchivePlayer::password() const { return m_password; }
void HikvisionArchivePlayer::setPassword(const QString &pw) {
    if (m_password != pw) {
        QString oldIp = m_recorderIp;
        LONG oldUserId = m_lUserID.exchange(-1);
        m_password = pw;
        emit passwordChanged();

        QMetaObject::invokeMethod(m_worker, [this, oldIp, oldUserId]() {
            cleanupPlayback();
            if (oldUserId >= 0) {
                if (HikvisionManager::instance()) {
                    HikvisionManager::instance()->logoutShared(oldIp);
                } else {
                    NET_DVR_Logout(oldUserId);
                }
            }
        }, Qt::QueuedConnection);
    }
}

qint64 HikvisionArchivePlayer::currentPlayheadMs() const { return m_currentPlayheadMs; }
bool HikvisionArchivePlayer::isPlaying() const { return m_isPlaying; }

bool HikvisionArchivePlayer::ensureLogin(const QString &ip, int port, const QString &user, const QString &pass)
{
    static bool s_sdkInit = false;
    if (!s_sdkInit) {
        NET_DVR_Init();
        s_sdkInit = true;
    }

    if (m_lUserID >= 0) return true;
    if (ip.isEmpty()) {
        qWarning() << "[HikArchive] ensureLogin: recorderIp is EMPTY, cannot login";
        return false;
    }

    NET_DVR_DEVICEINFO_V40 deviceInfo;
    std::memset(&deviceInfo, 0, sizeof(NET_DVR_DEVICEINFO_V40));

    HikvisionManager* mgr = HikvisionManager::instance();
    if (mgr) {
        m_lUserID = mgr->loginShared(ip, port, user, pass, deviceInfo);
    } else {
        qWarning() << "[HikArchive] HikvisionManager instance is null, falling back to direct login!";
        NET_DVR_USER_LOGIN_INFO loginInfo;
        std::memset(&loginInfo, 0, sizeof(NET_DVR_USER_LOGIN_INFO));
        std::strncpy(loginInfo.sDeviceAddress, ip.toUtf8().constData(), sizeof(loginInfo.sDeviceAddress) - 1);
        loginInfo.wPort = static_cast<WORD>(port);
        std::strncpy(loginInfo.sUserName, user.toUtf8().constData(), sizeof(loginInfo.sUserName) - 1);
        std::strncpy(loginInfo.sPassword, pass.toUtf8().constData(), sizeof(loginInfo.sPassword) - 1);
        loginInfo.bUseAsynLogin = FALSE;
        loginInfo.byLoginMode = 0;

        m_lUserID = NET_DVR_Login_V40(&loginInfo, &deviceInfo);
    }

    if (m_lUserID < 0) {
        DWORD err = NET_DVR_GetLastError();
        qWarning() << "[HikArchive] Login FAILED for IP:" << ip << "Error:" << err;
        return false;
    }
    
    // Compute real SDK channel ID from logical channel ID
    m_realSdkChannel = m_channelId;
    if (deviceInfo.struDeviceV30.byChanNum == 0 && deviceInfo.struDeviceV30.byIPChanNum > 0) {
        // Pure NVR (only IP cameras)
        m_realSdkChannel = m_channelId + deviceInfo.struDeviceV30.byStartDChan - 1;
    } else if (deviceInfo.struDeviceV30.byChanNum > 0 && m_channelId > deviceInfo.struDeviceV30.byChanNum) {
        // Hybrid DVR: IP camera requested (channel ID > analog channels)
        m_realSdkChannel = deviceInfo.struDeviceV30.byStartDChan + (m_channelId - deviceInfo.struDeviceV30.byChanNum) - 1;
    } else if (deviceInfo.struDeviceV30.byChanNum > 0 && m_channelId <= deviceInfo.struDeviceV30.byChanNum) {
        // DVR: Analog camera requested
        m_realSdkChannel = m_channelId + deviceInfo.struDeviceV30.byStartChan - 1;
    }

    qDebug() << "[HikArchive] Login SUCCESS. UserID:" << m_lUserID.load()
             << "StartChan:" << deviceInfo.struDeviceV30.byStartChan
             << "ChanNum:" << deviceInfo.struDeviceV30.byChanNum
             << "IPChanNum:" << deviceInfo.struDeviceV30.byIPChanNum
             << "StartDChan:" << deviceInfo.struDeviceV30.byStartDChan
             << "Logical Chan:" << m_channelId << "-> Real SDK Chan:" << m_realSdkChannel;
    return true;
}

void HikvisionArchivePlayer::playAtTime(const QDateTime &dateTime)
{
    qDebug() << "[HikArchive] playAtTime called with:" << dateTime
             << "recorderIp=" << m_recorderIp
             << "logical channelId=" << m_channelId
             << "username=" << m_username;

    // Capture credentials by value on the GUI thread
    QString ip = m_recorderIp;
    int port = m_port;
    QString user = m_username;
    QString pass = m_password;
    int channelId = m_channelId;

    QMetaObject::invokeMethod(m_worker, [this, dateTime, ip, port, user, pass, channelId]() {
        cleanupPlayback();

        if (!ensureLogin(ip, port, user, pass)) {
            qWarning() << "[HikArchive] Cannot play - login failed";
            return;
        }

        qDebug() << "[HikArchive] Requesting playback at" << dateTime << "on channel" << channelId;

        NET_DVR_TIME startTime;
        startTime.dwYear = dateTime.date().year();
        startTime.dwMonth = dateTime.date().month();
        startTime.dwDay = dateTime.date().day();
        startTime.dwHour = dateTime.time().hour();
        startTime.dwMinute = dateTime.time().minute();
        startTime.dwSecond = dateTime.time().second();

        // Default stop time = end of day
        NET_DVR_TIME stopTime = startTime;
        stopTime.dwHour = 23;
        stopTime.dwMinute = 59;
        stopTime.dwSecond = 59;

        qDebug() << "[HikArchive] Start:" << startTime.dwYear << "-" << startTime.dwMonth << "-" << startTime.dwDay
                 << startTime.dwHour << ":" << startTime.dwMinute << ":" << startTime.dwSecond;
        qDebug() << "[HikArchive] Stop:" << stopTime.dwYear << "-" << stopTime.dwMonth << "-" << stopTime.dwDay
                 << stopTime.dwHour << ":" << stopTime.dwMinute << ":" << stopTime.dwSecond;

        NET_DVR_VOD_PARA vodPara;
        std::memset(&vodPara, 0, sizeof(NET_DVR_VOD_PARA));
        vodPara.dwSize = sizeof(NET_DVR_VOD_PARA);
        vodPara.struIDInfo.dwChannel = m_realSdkChannel;
        vodPara.struBeginTime = startTime;
        vodPara.struEndTime = stopTime;
        vodPara.hWnd = 0;
        vodPara.byStreamType = 0; // 0-main stream
        vodPara.byDrawFrame = 0;

        LONG playHandle = NET_DVR_PlayBackByTime_V40(m_lUserID, &vodPara);
        if (playHandle < 0) {
            DWORD err = NET_DVR_GetLastError();
            qWarning() << "[HikArchive] PlayBackByTime FAILED. Error:" << err << "Channel used:" << m_realSdkChannel;
            
            // Auto-recovery: Force a shared logout, recreate session and retry
            qDebug() << "[HikArchive] Attempting to force shared relogin and retry playback...";
            LONG oldUserId = m_lUserID.exchange(-1);
            if (oldUserId >= 0) {
                if (HikvisionManager::instance()) {
                    HikvisionManager::instance()->forceLogoutShared(ip);
                } else {
                    NET_DVR_Logout(oldUserId);
                }
            }
            
            if (!ensureLogin(ip, port, user, pass)) {
                qWarning() << "[HikArchive] Retry login failed, aborting playback.";
                return;
            }
            
            qDebug() << "[HikArchive] Retry PlayBackByTime on new UserID:" << m_lUserID.load() << "and Channel:" << m_realSdkChannel;
            playHandle = NET_DVR_PlayBackByTime_V40(m_lUserID, &vodPara);
            if (playHandle < 0) {
                qWarning() << "[HikArchive] Retry PlayBackByTime FAILED. Error:" << NET_DVR_GetLastError();
                return;
            }
            qDebug() << "[HikArchive] Retry PlayBackByTime SUCCESS. Handle:" << playHandle;
        }
        qDebug() << "[HikArchive] PlayBackByTime SUCCESS. Handle:" << playHandle;

        // Allocate a free port for decoding
        LONG tempPort = -1;
        if (!PlayM4_GetPort(&tempPort)) {
            qWarning() << "[HikArchive] PlayM4_GetPort FAILED.";
            NET_DVR_StopPlayBack(playHandle);
            return;
        }
        qDebug() << "[HikArchive] PlayM4 port allocated:" << tempPort;

        {
            std::lock_guard<std::mutex> lock(m_stateMutex);
            m_lPlayHandle = playHandle;
            m_nPort = tempPort;
        }

        if (!PlayM4_SetStreamOpenMode(tempPort, STREAME_FILE)) {
            qWarning() << "[HikArchive] PlayM4_SetStreamOpenMode FAILED.";
        }

        // Set network stream callback to pump data into the PlayM4 decoder
        if (!NET_DVR_SetPlayDataCallBack_V40(playHandle, PlayDataCallBack, this)) {
            DWORD err = NET_DVR_GetLastError();
            qWarning() << "[HikArchive] SetPlayDataCallBack_V40 FAILED. Error:" << err;
            cleanupPlayback();
            return;
        }
        qDebug() << "[HikArchive] PlayDataCallBack registered.";
        
        // Start playback control
        if (!NET_DVR_PlayBackControl_V40(playHandle, NET_DVR_PLAYSTART, nullptr, 0, nullptr, nullptr)) {
            DWORD err = NET_DVR_GetLastError();
            qWarning() << "[HikArchive] NET_DVR_PLAYSTART FAILED. Error:" << err;
            cleanupPlayback();
            return;
        }
        qDebug() << "[HikArchive] Playback STARTED successfully!";

        // Send PLAYSTARTAUDIO to ensure NVR streams audio to us
        if (!NET_DVR_PlayBackControl_V40(playHandle, NET_DVR_PLAYSTARTAUDIO, nullptr, 0, nullptr, nullptr)) {
            qWarning() << "[HikArchive] NET_DVR_PLAYSTARTAUDIO FAILED. Error:" << NET_DVR_GetLastError();
        } else {
            qDebug() << "[HikArchive] NET_DVR_PLAYSTARTAUDIO sent successfully!";
        }

        {
            std::lock_guard<std::mutex> lock(m_stateMutex);
            m_sysHeadReceived = false;
            m_isPlaying = true;
        }
        QMetaObject::invokeMethod(this, [this]() {
            emit playingChanged();
        }, Qt::QueuedConnection);
    }, Qt::QueuedConnection);
}

void HikvisionArchivePlayer::setPlaybackSpeed(int speedMultiplier)
{
    m_currentSpeedMultiplier = speedMultiplier;
    if (m_lPlayHandle < 0) return;

    if (std::abs(speedMultiplier) == 8) {
        qWarning() << "[HikArchive] setPlaybackSpeed: 8x playback speed is disabled because it is never smooth";
        return;
    }

    QMetaObject::invokeMethod(m_worker, [this, speedMultiplier]() {
        LONG handle = m_lPlayHandle;
        LONG port = m_nPort;
        if (handle < 0) return;

        qDebug() << "[HikArchive] setPlaybackSpeed:" << speedMultiplier;

        // 1. Reset NVR speed to normal (always 1x first to clear any FAST/SLOW states)
        if (!NET_DVR_PlayBackControl_V40(handle, NET_DVR_PLAYNORMAL, nullptr, 0, nullptr, nullptr)) {
            qWarning() << "[HikArchive] setPlaybackSpeed NORMAL failed:" << NET_DVR_GetLastError();
        }

        // 2. Reset PlayM4 speed to normal
        if (port != -1) {
            PlayM4_Play(port, 0);
        }

        // 3. Set the direction on the NVR stream and PlayM4 decoder
        if (speedMultiplier < 0) {
            if (!NET_DVR_PlayBackControl_V40(handle, NET_DVR_PLAY_REVERSE, nullptr, 0, nullptr, nullptr)) {
                qWarning() << "[HikArchive] NET_DVR_PLAY_REVERSE failed:" << NET_DVR_GetLastError();
            }
            // Keep decoding forward! The NVR will reverse and stream the frames sequentially.
            if (port != -1) {
                if (!PlayM4_Play(port, 0)) {
                    qWarning() << "[HikArchive] PlayM4_Play forward (for reverse) failed:" << PlayM4_GetLastError(port);
                }
            }
        } else {
            if (!NET_DVR_PlayBackControl_V40(handle, NET_DVR_PLAY_FORWARD, nullptr, 0, nullptr, nullptr)) {
                qWarning() << "[HikArchive] NET_DVR_PLAY_FORWARD failed:" << NET_DVR_GetLastError();
            }
            if (port != -1) {
                if (!PlayM4_Play(port, 0)) {
                    qWarning() << "[HikArchive] PlayM4_Play forward failed:" << PlayM4_GetLastError(port);
                }
            }
        }

        // 4. Apply step-by-step fast commands if speed multiplier is > 1
        int absSpeed = std::abs(speedMultiplier);
        if (absSpeed > 1) {
            int steps = (absSpeed == 2) ? 1 : ((absSpeed == 4) ? 2 : 3);
            for (int i = 0; i < steps; ++i) {
                if (!NET_DVR_PlayBackControl_V40(handle, NET_DVR_PLAYFAST, nullptr, 0, nullptr, nullptr)) {
                    qWarning() << "[HikArchive] setPlaybackSpeed FAST step" << i << "failed:" << NET_DVR_GetLastError();
                }
                if (port != -1) {
                    PlayM4_Fast(port);
                }
            }
        }
    }, Qt::QueuedConnection);
}

void HikvisionArchivePlayer::pause()
{
    if (m_lPlayHandle >= 0) {
        QMetaObject::invokeMethod(m_worker, [this]() {
            LONG handle = m_lPlayHandle;
            LONG port = m_nPort;
            if (handle >= 0) {
                if (port != -1) PlayM4_Pause(port, 1);
                NET_DVR_PlayBackControl_V40(handle, NET_DVR_PLAYPAUSE, nullptr, 0, nullptr, nullptr);
                m_isPlaying = false;
                QMetaObject::invokeMethod(this, [this]() {
                    emit playingChanged();
                }, Qt::QueuedConnection);

                if (m_fps != 0) {
                    m_fps = 0;
                    m_fpsCounter = 0;
                    m_lastFpsTime = 0;
                    QMetaObject::invokeMethod(this, [this]() {
                        emit fpsChanged();
                    }, Qt::QueuedConnection);
                }
            }
        }, Qt::QueuedConnection);
    }
}

void HikvisionArchivePlayer::resume()
{
    if (m_lPlayHandle >= 0) {
        QMetaObject::invokeMethod(m_worker, [this]() {
            LONG handle = m_lPlayHandle;
            LONG port = m_nPort;
            if (handle >= 0) {
                if (port != -1) PlayM4_Pause(port, 0);
                NET_DVR_PlayBackControl_V40(handle, NET_DVR_PLAYRESTART, nullptr, 0, nullptr, nullptr);
                NET_DVR_PlayBackControl_V40(handle, NET_DVR_PLAYNORMAL, nullptr, 0, nullptr, nullptr);
                m_isPlaying = true;
                QMetaObject::invokeMethod(this, [this]() {
                    emit playingChanged();
                }, Qt::QueuedConnection);
            }
        }, Qt::QueuedConnection);
    }
}

void HikvisionArchivePlayer::stop()
{
    qDebug() << "[HikArchive] stop() called from QML!";
    m_currentSpeedMultiplier = 1;
    QMetaObject::invokeMethod(m_worker, [this]() {
        cleanupPlayback();
    }, Qt::QueuedConnection);
}

void HikvisionArchivePlayer::setVolume(double volume)
{
    if (volume < 0.0) volume = 0.0;
    if (volume > 1.0) volume = 1.0;

    if (qFuzzyCompare(m_volume, volume)) return;

    m_volume = volume;
    emit volumeChanged();

    std::lock_guard<std::mutex> lock(m_audioMutex);
    if (m_audioOutput) {
        m_audioOutput->setVolume(m_muted ? 0.0 : m_volume);
    }
}

void HikvisionArchivePlayer::setMuted(bool muted)
{
    if (m_muted == muted) return;

    m_muted = muted;
    emit mutedChanged();

    std::lock_guard<std::mutex> lock(m_audioMutex);
    if (m_audioOutput) {
        m_audioOutput->setVolume(m_muted ? 0.0 : m_volume);
    }
}

bool HikvisionArchivePlayer::hasActiveStream() const
{
    return m_lPlayHandle >= 0;
}

bool HikvisionArchivePlayer::hasReceivedFrames() const
{
    std::lock_guard<std::mutex> lock(m_imageMutex);
    return !m_currentImage.isNull();
}


static std::atomic<int> s_dataCallbackCount{0};
static std::atomic<int> s_decCallbackCount{0};

void HikvisionArchivePlayer::PlayDataCallBack(LONG lPlayHandle, DWORD dwDataType, BYTE *pBuffer, DWORD dwBufSize, void *pUser)
{
    g_networkBytesAccumulator.fetch_add(dwBufSize, std::memory_order_relaxed);

    HikvisionArchivePlayer* player = nullptr;
    {
        std::lock_guard<std::mutex> lock(s_activePlayersMutex);
        if (s_activePlayers.find(static_cast<HikvisionArchivePlayer*>(pUser)) != s_activePlayers.end()) {
            player = static_cast<HikvisionArchivePlayer*>(pUser);
        }
    }

    if (!player) {
        return;
    }

    LONG activeHandle = -1;
    LONG activePort = -1;
    bool sysHeadReceived = false;
    bool isPlaying = false;
    uint64_t activeSessionId = 0;

    {
        std::lock_guard<std::mutex> lock(player->m_stateMutex);
        activeHandle = player->m_lPlayHandle.load();
        activePort = player->m_nPort.load();
        sysHeadReceived = player->m_sysHeadReceived.load();
        isPlaying = player->m_isPlaying;
        activeSessionId = player->m_playbackSessionId.load();
    }

    if (lPlayHandle != activeHandle || activeHandle < 0) {
        // Discard late data from a previously stopped session to prevent stream/decoder corruption
        return;
    }

    int count = ++s_dataCallbackCount;
    if (count <= 5 || count % 100 == 0) {
        qDebug() << "[HikArchive] PlayDataCallBack #" << count
                 << "type=" << dwDataType << "size=" << dwBufSize
                 << "port=" << activePort;
    }

    if (dwDataType == NET_DVR_SYSHEAD) {
        if (player->m_playbackSessionId.load() != activeSessionId) {
            return;
        }
        {
            std::lock_guard<std::mutex> lock(player->m_stateMutex);
            player->m_sysHeadReceived = true;
        }
        qDebug() << "[HikArchive] Got SYSHEAD (stream header), size=" << dwBufSize;

        if (activePort < 0) {
            qWarning() << "[HikArchive] SYSHEAD received but activePort is invalid!";
            return;
        }

        if (!PlayM4_OpenStream(activePort, pBuffer, dwBufSize, 4 * 1024 * 1024)) {
            DWORD playErr = PlayM4_GetLastError(activePort);
            qWarning() << "[HikArchive] PlayM4_OpenStream FAILED. PlayM4 error:" << playErr;
            return;
        }
        qDebug() << "[HikArchive] PlayM4_OpenStream OK";

        if (!PlayM4_SetDisplayBuf(activePort, 15)) {
            qWarning() << "[HikArchive] PlayM4_SetDisplayBuf FAILED. PlayM4 error:" << PlayM4_GetLastError(activePort);
        } else {
            qDebug() << "[HikArchive] PlayM4_SetDisplayBuf (15 frames) OK";
        }
        
        // Register this instance in port map
        {
            std::lock_guard<std::mutex> lock(s_portMapMutex);
            s_portMap[activePort] = player;
        }

        if (!PlayM4_SetDecCallBack(activePort, DecCallBack)) {
            DWORD playErr = PlayM4_GetLastError(activePort);
            qWarning() << "[HikArchive] PlayM4_SetDecCallBack FAILED. PlayM4 error:" << playErr;
        } else {
            qDebug() << "[HikArchive] PlayM4_SetDecCallBack OK";
        }
        
        if (!PlayM4_Play(activePort, 0)) {
            DWORD playErr = PlayM4_GetLastError(activePort);
            qWarning() << "[HikArchive] PlayM4_Play FAILED. PlayM4 error:" << playErr;
        } else {
            qDebug() << "[HikArchive] PlayM4_Play OK - decoder started!";

            // Restore playback speed if it's not 1x
            if (player->m_currentSpeedMultiplier != 1) {
                qDebug() << "[HikArchive] Restoring playback speed to:" << player->m_currentSpeedMultiplier;
                player->setPlaybackSpeed(player->m_currentSpeedMultiplier);
            }
            
            // Try to set separate audio callback first (may fail on Linux with Error 16)
            bool audioCallbackRegistered = PlayM4_SetAudioCallBack(activePort, AudioCallBack, reinterpret_cast<long>(player));
            
            // Always start sound to enable audio decoding within PlayM4
            bool soundStarted = PlayM4_PlaySound(activePort);
            if (!soundStarted) {
                qDebug() << "[HikArchive] PlayM4_PlaySound failed, trying PlayM4_PlaySoundShare...";
                soundStarted = PlayM4_PlaySoundShare(activePort);
            }

            if (soundStarted) {
                qDebug() << "[HikArchive] Sound playback successfully started on port" << activePort;
                player->m_soundPlaying = true;
                // UNCONDITIONALLY mute direct SDK ALSA sound rendering to prevent ALSA/PulseAudio lockups
                PlayM4_SetVolume(activePort, 0);
            } else {
                qWarning() << "[HikArchive] Failed to start sound playback! Error:" << PlayM4_GetLastError(activePort);
                player->m_soundPlaying = false;
            }

            if (audioCallbackRegistered) {
                qDebug() << "[HikArchive] PlayM4_SetAudioCallBack registered OK on port" << activePort;
            } else {
                qDebug() << "[HikArchive] PlayM4_SetAudioCallBack failed with error" << PlayM4_GetLastError(activePort)
                         << "- audio will be intercepted and decoded via DecCallBack instead.";
            }
        }
    } else if (dwDataType == NET_DVR_STREAMDATA) {
        if (!sysHeadReceived) {
            return; // Ignore late data from a previous stopped playback session
        }
        if (activePort < 0) {
            return;
        }
        int retryCount = 0;
        while (!PlayM4_InputData(activePort, pBuffer, dwBufSize)) {
            LONG currentHandle = -1;
            LONG currentPort = -1;
            bool currentIsPlaying = false;
            uint64_t currentSessionId = 0;
            {
                std::lock_guard<std::mutex> lock(player->m_stateMutex);
                currentHandle = player->m_lPlayHandle.load();
                currentPort = player->m_nPort.load();
                currentIsPlaying = player->m_isPlaying;
                currentSessionId = player->m_playbackSessionId.load();
            }
            if (currentHandle != activeHandle || currentPort != activePort || !currentIsPlaying || currentSessionId != activeSessionId) {
                break;
            }
            DWORD playErr = PlayM4_GetLastError(activePort);
            if (playErr == 11) { // PLAYM4_BUF_OVER
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
                retryCount++;
                if (retryCount % 200 == 0) {
                    qDebug() << "[HikArchive] PlayM4_InputData buffer full, retrying..." << retryCount;
                }
                continue;
            }
            if (count <= 5 || count % 500 == 0) {
                qDebug() << "[HikArchive] PlayM4_InputData failed at #" << count << "PlayM4 error:" << playErr << "Retries:" << retryCount;
            }
            break;
        }
    } else {
        qDebug() << "[HikArchive] PlayDataCallBack unknown type:" << dwDataType;
    }
}

// In Linux 64-bit GCC, 'long' is 64-bit, but Hikvision SDK was compiled with 32-bit fields!
// We must read it as an array of 32-bit ints.
struct FRAME_INFO_32 {
    int32_t nWidth;
    int32_t nHeight;
    int32_t nStamp;
    int32_t nType;
    int32_t nFrameRate;
    uint32_t dwFrameNum;
};

void HikvisionArchivePlayer::DecCallBack(long nPort, char *pBuf, long nSize, FRAME_INFO *pFrameInfo, long nReserved1, long nReserved2)
{
    Q_UNUSED(nReserved1);
    Q_UNUSED(nReserved2);

    HikvisionArchivePlayer* player = nullptr;
    {
        std::lock_guard<std::mutex> lock(s_portMapMutex);
        auto it = s_portMap.find(nPort);
        if (it != s_portMap.end()) {
            player = it->second;
        }
    }

    if (player) {
        std::lock_guard<std::mutex> lock(s_activePlayersMutex);
        if (s_activePlayers.find(player) == s_activePlayers.end()) {
            player = nullptr;
        }
    }

    if (!player || !pFrameInfo) return;

    FRAME_INFO_32* info = reinterpret_cast<FRAME_INFO_32*>(pFrameInfo);

    int count = ++s_decCallbackCount;
    if (count <= 3 || count % 100 == 0) {
        qDebug() << "[HikArchive] DecCallBack #" << count
                 << "type=" << info->nType
                 << "size=" << nSize
                 << "w=" << info->nWidth
                 << "h=" << info->nHeight;
    }

    uint64_t activeSessionId = player->m_playbackSessionId.load();

    if (info->nType == T_YV12) {

        int width = info->nWidth;
        int height = info->nHeight;
        
        if (width <= 0 || height <= 0 || nSize < width * height * 3 / 2) {
            qWarning() << "[HikArchive] DecCallBack: invalid frame dimensions w=" << width << "h=" << height << "size=" << nSize;
            return;
        }

        if (player->m_pendingTasks.load() + player->m_guiPendingTasks.load() >= 5) {
            // Drop frame to prevent thread pools/queues from filling up
            return;
        }
        
        std::shared_ptr<FrameBuffer> fb = player->getOrCreateFrameBuffer(width, height);
        if (!fb) return;

        // Copy raw YV12 data to the frame buffer
        std::memcpy(fb->yv12Data.data(), pBuf, nSize);

        player->m_pendingTasks++;

        auto* task = new YV12ToRGBTask(player, fb, activeSessionId);
        QThreadPool::globalInstance()->start(task);
    }
    else if (info->nType == T_AUDIO16) {
        if (nSize <= 0 || nSize > 1024 * 1024) {
            return; // Safety guard against invalid/corrupt audio frames
        }
        if (player->m_guiPendingTasks.load() >= 15) {
            return; // Drop audio frames if GUI is frozen to prevent memory expansion
        }

        int sampleRate = 0;
        // 1. Instantly determine rate based on frame size (extremely robust, immune to network jitter)
        if (nSize == 640 || nSize == 320) {
            sampleRate = 8000;
        } else if (nSize == 2048 || nSize == 1024) {
            sampleRate = 16000;
        } else {
            // 2. Fallback to dynamic stamp calculation
            long nStamp = info->nStamp;
            long lastStamp = player->m_lastAudioStamp.exchange(nStamp);
            if (lastStamp > 0 && nStamp > lastStamp) {
                long deltaStamp = nStamp - lastStamp;
                if (deltaStamp > 0 && deltaStamp < 200) {
                    double dynamicRate = static_cast<double>(nSize) * 500.0 / deltaStamp;
                    if (dynamicRate > 7000 && dynamicRate < 9000) {
                        sampleRate = 8000;
                    } else if (dynamicRate > 10000 && dynamicRate < 12000) {
                        sampleRate = 11025;
                    } else if (dynamicRate > 14000 && dynamicRate < 18000) {
                        sampleRate = 16000;
                    } else if (dynamicRate > 20000 && dynamicRate < 24000) {
                        sampleRate = 22050;
                    } else if (dynamicRate > 28000 && dynamicRate < 36000) {
                        sampleRate = 32000;
                    } else if (dynamicRate > 40000 && dynamicRate < 46000) {
                        sampleRate = 44100;
                    } else if (dynamicRate > 46000 && dynamicRate < 50000) {
                        sampleRate = 48000;
                    }
                }
            }
        }

        if (sampleRate <= 0) {
            return; // Ignore unrecognized or highly jittery/unstable rates
        }

        QByteArray rawData(pBuf, nSize);
        QPointer<HikvisionArchivePlayer> pPlayer = player;
        QMetaObject::invokeMethod(player, [pPlayer, rawData, sampleRate, activeSessionId]() {
            if (!pPlayer) return;
            if (pPlayer->m_playbackSessionId.load() != activeSessionId) return;

            pPlayer->initAudioOutput(sampleRate, 1, activeSessionId);

            std::lock_guard<std::mutex> lock(pPlayer->m_audioMutex);
            if (pPlayer->m_audioOutputDevice && !pPlayer->m_muted) {
                int outRate = pPlayer->m_audioFormat.sampleRate();
                int outChannels = pPlayer->m_audioFormat.channelCount();

                QByteArray resampled = resampleAudio(rawData.constData(), rawData.size(), sampleRate, outRate, outChannels);
                if (!resampled.isEmpty()) {
                    pPlayer->m_audioOutputDevice->write(resampled);
                }
            }
        }, Qt::QueuedConnection);
    }
    else if (info->nType == T_AUDIO8) {
        if (nSize <= 0 || nSize > 1024 * 1024) {
            return; // Safety guard against invalid/corrupt audio frames
        }
        if (player->m_guiPendingTasks.load() >= 15) {
            return; // Drop audio frames if GUI is frozen to prevent memory expansion
        }

        int sampleRate = 0;
        // 1. Instantly determine rate based on frame size (extremely robust, immune to network jitter)
        if (nSize == 320 || nSize == 160) {
            sampleRate = 8000;
        } else if (nSize == 1024 || nSize == 512) {
            sampleRate = 16000;
        } else {
            // 2. Fallback to dynamic stamp calculation
            long nStamp = info->nStamp;
            long lastStamp = player->m_lastAudioStamp.exchange(nStamp);
            if (lastStamp > 0 && nStamp > lastStamp) {
                long deltaStamp = nStamp - lastStamp;
                if (deltaStamp > 0 && deltaStamp < 200) {
                    double dynamicRate = static_cast<double>(nSize) * 1000.0 / deltaStamp;
                    if (dynamicRate > 7000 && dynamicRate < 9000) {
                        sampleRate = 8000;
                    } else if (dynamicRate > 10000 && dynamicRate < 12000) {
                        sampleRate = 11025;
                    } else if (dynamicRate > 14000 && dynamicRate < 18000) {
                        sampleRate = 16000;
                    } else if (dynamicRate > 20000 && dynamicRate < 24000) {
                        sampleRate = 22050;
                    } else if (dynamicRate > 28000 && dynamicRate < 36000) {
                        sampleRate = 32000;
                    } else if (dynamicRate > 40000 && dynamicRate < 46000) {
                        sampleRate = 44100;
                    } else if (dynamicRate > 46000 && dynamicRate < 50000) {
                        sampleRate = 48000;
                    }
                }
            }
        }

        if (sampleRate <= 0) {
            return; // Ignore unrecognized or highly jittery/unstable rates
        }

        QByteArray rawData;
        rawData.resize(nSize * 2);
        int16_t* dst = reinterpret_cast<int16_t*>(rawData.data());
        const uint8_t* src = reinterpret_cast<const uint8_t*>(pBuf);
        for (int i = 0; i < nSize; ++i) {
            dst[i] = static_cast<int16_t>((static_cast<int>(src[i]) - 128) * 256);
        }

        QPointer<HikvisionArchivePlayer> pPlayer = player;
        QMetaObject::invokeMethod(player, [pPlayer, rawData, sampleRate, activeSessionId]() {
            if (!pPlayer) return;
            if (pPlayer->m_playbackSessionId.load() != activeSessionId) return;

            pPlayer->initAudioOutput(sampleRate, 1, activeSessionId);

            std::lock_guard<std::mutex> lock(pPlayer->m_audioMutex);
            if (pPlayer->m_audioOutputDevice && !pPlayer->m_muted) {
                int outRate = pPlayer->m_audioFormat.sampleRate();
                int outChannels = pPlayer->m_audioFormat.channelCount();

                QByteArray resampled = resampleAudio(rawData.constData(), rawData.size(), sampleRate, outRate, outChannels);
                if (!resampled.isEmpty()) {
                    pPlayer->m_audioOutputDevice->write(resampled);
                }
            }
        }, Qt::QueuedConnection);
    }
}

std::shared_ptr<HikvisionArchivePlayer::FrameBuffer> HikvisionArchivePlayer::getOrCreateFrameBuffer(int width, int height)
{
    size_t yv12Size = static_cast<size_t>(width) * height * 3 / 2;
    size_t rgbSize = static_cast<size_t>(width) * height * 4;

    std::lock_guard<std::mutex> lock(m_poolMutex);
    for (auto& fb : m_frameBufferPool) {
        if (!fb->inUse.load()) {
            if (fb->yv12Data.size() < yv12Size) {
                fb->yv12Data.resize(yv12Size);
            }
            if (fb->rgbData.size() < rgbSize) {
                fb->rgbData.resize(rgbSize);
            }
            fb->width = width;
            fb->height = height;
            fb->inUse = true;
            return fb;
        }
    }
    auto fb = std::make_shared<FrameBuffer>();
    fb->yv12Data.resize(yv12Size);
    fb->rgbData.resize(rgbSize);
    fb->width = width;
    fb->height = height;
    fb->inUse = true;
    m_frameBufferPool.push_back(fb);
    return fb;
}

void HikvisionArchivePlayer::updateImage(const QImage &img)
{
    bool sizeChanged = false;
    {
        std::lock_guard<std::mutex> lock(m_imageMutex);
        if (m_currentImage.size() != img.size()) {
            sizeChanged = true;
        }
        m_currentImage = img;
    }
    if (sizeChanged) {
        emit videoSizeChanged();
    }

    // Compute display FPS on the GUI thread
    m_fpsCounter++;
    qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    if (m_lastFpsTime == 0) {
        m_lastFpsTime = nowMs;
    }
    qint64 elapsedMs = nowMs - m_lastFpsTime;
    if (elapsedMs >= 1000) {
        int calculatedFps = qRound(m_fpsCounter * 1000.0 / elapsedMs);
        if (m_fps != calculatedFps) {
            m_fps = calculatedFps;
            emit fpsChanged();
        }
        m_fpsCounter = 0;
        m_lastFpsTime = nowMs;
    }

    update();
}

void HikvisionArchivePlayer::paint(QPainter *painter)
{
    std::lock_guard<std::mutex> lock(m_imageMutex);
    painter->fillRect(boundingRect(), Qt::black);
    if (!m_currentImage.isNull()) {
        QRectF targetRect = boundingRect();
        qreal imgRatio = (qreal)m_currentImage.width() / m_currentImage.height();
        qreal rectRatio = targetRect.width() / targetRect.height();
        
        if (imgRatio > rectRatio) {
            qreal newHeight = targetRect.width() / imgRatio;
            qreal yOffset = (targetRect.height() - newHeight) / 2.0;
            targetRect = QRectF(targetRect.x(), targetRect.y() + yOffset, targetRect.width(), newHeight);
        } else {
            qreal newWidth = targetRect.height() * imgRatio;
            qreal xOffset = (targetRect.width() - newWidth) / 2.0;
            targetRect = QRectF(targetRect.x() + xOffset, targetRect.y(), newWidth, targetRect.height());
        }
        painter->drawImage(targetRect, m_currentImage);
    } else {
        painter->setPen(Qt::white);
        QString msg = m_playerStatusMessage;
        if (msg.isEmpty()) {
            msg = "Ładowanie archiwum Hikvision...";
        }
        painter->drawText(boundingRect(), Qt::AlignCenter, msg);
    }
}

int HikvisionArchivePlayer::videoWidth() const
{
    std::lock_guard<std::mutex> lock(m_imageMutex);
    return m_currentImage.width();
}

int HikvisionArchivePlayer::videoHeight() const
{
    std::lock_guard<std::mutex> lock(m_imageMutex);
    return m_currentImage.height();
}

bool HikvisionArchivePlayer::saveCurrentFrame(const QString &path) const
{
    std::lock_guard<std::mutex> lock(m_imageMutex);
    if (m_currentImage.isNull()) {
        return false;
    }
    return m_currentImage.save(path, "JPG", 98);
}

void HikvisionArchivePlayer::initAudioOutput(int sampleRate, int channels, uint64_t sessionId)
{
    if (QThread::currentThread() != qApp->thread()) {
        QMetaObject::invokeMethod(this, [this, sampleRate, channels, sessionId]() {
            this->initAudioOutput(sampleRate, channels, sessionId);
        }, Qt::QueuedConnection);
        return;
    }

    if (m_playbackSessionId.load() != sessionId) {
        return;
    }

    // Sanity checks: reject invalid audio parameters from corrupted cameras to prevent crashes
    if (sampleRate < 4000 || sampleRate > 192000 || channels <= 0 || channels > 8) {
        qWarning() << "[HikArchive] initAudioOutput: Rejected unsupported audio parameters, sampleRate=" 
                   << sampleRate << "channels=" << channels;
        return;
    }

    if (sampleRate == m_lastProposedSampleRate) {
        m_sampleRateConsecutiveCount++;
    } else {
        m_lastProposedSampleRate = sampleRate;
        m_sampleRateConsecutiveCount = 1;
    }

    if (m_sampleRateConsecutiveCount < 5) {
        return; // Wait for stable rate estimate
    }

    std::lock_guard<std::mutex> lock(m_audioMutex);
    if (m_audioOutput) {
        if (m_audioFormat.sampleRate() == sampleRate && m_audioFormat.channelCount() == channels) {
            return;
        }

        // Rate/Channels changed!
        qint64 now = QDateTime::currentMSecsSinceEpoch();
        if (now - m_lastAudioInitTime < 2000) {
            // Avoid rapid recreation thrashing to prevent PulseAudio/ALSA crashes
            return;
        }

        m_audioOutput->stop();
        m_audioOutput->deleteLater();
        m_audioOutput = nullptr;
        m_audioOutputDevice = nullptr;
    }

    m_lastAudioInitTime = QDateTime::currentMSecsSinceEpoch();

    m_audioFormat.setSampleRate(sampleRate);
    m_audioFormat.setChannelCount(channels);
    m_audioFormat.setSampleSize(16);
    m_audioFormat.setCodec("audio/pcm");
    m_audioFormat.setByteOrder(QAudioFormat::LittleEndian);
    m_audioFormat.setSampleType(QAudioFormat::SignedInt);

    QAudioDeviceInfo defaultDeviceInfo = QAudioDeviceInfo::defaultOutputDevice();
    if (defaultDeviceInfo.isNull()) {
        qWarning() << "[HikArchive] No default audio output device found! Audio will be muted.";
        return;
    }

    qDebug() << "[HikArchive] Default audio device:" << defaultDeviceInfo.deviceName();
    if (!defaultDeviceInfo.isFormatSupported(m_audioFormat)) {
        qWarning() << "[HikArchive] Requested audio format not supported, using nearest format.";
        m_audioFormat = defaultDeviceInfo.nearestFormat(m_audioFormat);
        qDebug() << "[HikArchive] Nearest format chosen: sampleRate=" << m_audioFormat.sampleRate()
                 << "channels=" << m_audioFormat.channelCount()
                 << "sampleSize=" << m_audioFormat.sampleSize()
                 << "codec=" << m_audioFormat.codec();
    }

    m_audioOutput = new QAudioOutput(defaultDeviceInfo, m_audioFormat, nullptr);
    m_audioOutput->setBufferSize(64000); // 64KB buffer to handle network jitter
    m_audioOutput->setVolume(m_muted ? 0.0 : m_volume);

    connect(m_audioOutput, &QAudioOutput::stateChanged, this, [this](QAudio::State state) {
        if (m_audioOutput) {
            qDebug() << "[HikArchive] QAudioOutput state changed to:" << state << "Error:" << m_audioOutput->error();
        }
    });

    m_audioOutputDevice = m_audioOutput->start();
    if (!m_audioOutputDevice) {
        if (m_audioOutput) {
            qWarning() << "[HikArchive] Failed to start QAudioOutput! Error:" << m_audioOutput->error();
        }
    } else {
        qDebug() << "[HikArchive] QAudioOutput started successfully with state:" << m_audioOutput->state()
                 << "bufferSize=" << m_audioOutput->bufferSize();
    }
}

void HikvisionArchivePlayer::AudioCallBack(long nPort, char * pAudioBuf, long nSize, long nStamp, long nType, long nUser)
{
    Q_UNUSED(nPort); Q_UNUSED(nStamp);
    HikvisionArchivePlayer* player = reinterpret_cast<HikvisionArchivePlayer*>(nUser);
    if (!player) return;

    {
        std::lock_guard<std::mutex> lock(s_activePlayersMutex);
        if (s_activePlayers.find(player) == s_activePlayers.end()) return;
    }

    if (player->m_nPort.load() != nPort) return;

    // G.722.1 (0x7001) uses 16000Hz, other codecs typically use 8000Hz (G.711, G.726, etc)
    int sampleRate = (nType == 0x7001) ? 16000 : 8000;
    uint64_t activeSessionId = player->m_playbackSessionId.load();

    QByteArray rawData(pAudioBuf, nSize);
    QPointer<HikvisionArchivePlayer> pPlayer = player;

    QMetaObject::invokeMethod(player, [pPlayer, rawData, sampleRate, activeSessionId]() {
        if (!pPlayer) return;
        if (pPlayer->m_playbackSessionId.load() != activeSessionId) return;

        pPlayer->initAudioOutput(sampleRate, 1, activeSessionId);

        std::lock_guard<std::mutex> lock(pPlayer->m_audioMutex);
        if (pPlayer->m_audioOutputDevice && !pPlayer->m_muted) {
            int outRate = pPlayer->m_audioFormat.sampleRate();
            int outChannels = pPlayer->m_audioFormat.channelCount();

            QByteArray resampled = resampleAudio(rawData.constData(), rawData.size(), sampleRate, outRate, outChannels);
            if (!resampled.isEmpty()) {
                pPlayer->m_audioOutputDevice->write(resampled);
            }
        }
    }, Qt::QueuedConnection);
}


