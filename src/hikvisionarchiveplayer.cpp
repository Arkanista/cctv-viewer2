#include "hikvisionarchiveplayer.h"
#include "hikvisionmanager.h"
#include "qmlav/src/qmlavdemuxer.h"
#include <QPainter>
#include <QDebug>
#include <QCoreApplication>
#include <QThreadPool>
#include <QRunnable>
#include <iostream>

// Hikvision PlayM4 decoder constants (usually YV12)
#define T_YV12 3

class YV12ToRGBTask : public QRunnable
{
public:
    YV12ToRGBTask(QPointer<HikvisionArchivePlayer> player, std::shared_ptr<HikvisionArchivePlayer::FrameBuffer> frame, LONG playHandle)
        : m_player(player), m_frame(frame), m_taskPlayHandle(playHandle)
    {
        setAutoDelete(true);
    }

    void run() override
    {
        if (!m_player || !m_frame) {
            if (m_frame) {
                m_frame->inUse = false;
            }
            return;
        }

        // Check if session has changed before starting expensive RGB conversion
        if (m_player->m_lPlayHandle.load() != m_taskPlayHandle) {
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

        if (!m_player || m_player->m_lPlayHandle.load() != m_taskPlayHandle) {
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
        QMetaObject::invokeMethod(pPlayer.data(), [pPlayer, img, playHandle = m_taskPlayHandle]() {
            if (pPlayer) {
                if (pPlayer->m_lPlayHandle.load() == playHandle) {
                    pPlayer->updateImage(img);
                }
                pPlayer->m_pendingTasks--;
            }
        }, Qt::QueuedConnection);
    }

private:
    QPointer<HikvisionArchivePlayer> m_player;
    std::shared_ptr<HikvisionArchivePlayer::FrameBuffer> m_frame;
    LONG m_taskPlayHandle;
};

HikvisionArchivePlayer::HikvisionArchivePlayer(QQuickItem *parent)
    : QQuickPaintedItem(parent)
{
    // The Hikvision SDK (HCNetSDK) requires NET_DVR_Init(). 
    // HikvisionManager already calls it.
    qDebug() << "[HikArchive] Component created";
}

HikvisionArchivePlayer::~HikvisionArchivePlayer()
{
    qDebug() << "[HikArchive] ~HikvisionArchivePlayer() DESTRUCTOR CALLED!";
    cleanupPlayback();
    if (m_lUserID >= 0) {
        if (HikvisionManager::instance()) {
            HikvisionManager::instance()->logoutShared(m_recorderIp);
        } else {
            NET_DVR_Logout(m_lUserID);
        }
        m_lUserID = -1;
    }
}

std::mutex s_portMapMutex;
static std::map<LONG, HikvisionArchivePlayer*> s_portMap;

void HikvisionArchivePlayer::cleanupPlayback()
{
    qDebug() << "[HikArchive] cleanupPlayback: m_lPlayHandle=" << m_lPlayHandle << "m_nPort=" << m_nPort << "m_lUserID=" << m_lUserID;

    if (m_lPlayHandle >= 0) {
        NET_DVR_StopPlayBack(m_lPlayHandle);
        m_lPlayHandle = -1;
    }

    if (m_nPort >= 0) {
        {
            std::lock_guard<std::mutex> lock(s_portMapMutex);
            s_portMap.erase(m_nPort);
        }
        PlayM4_Stop(m_nPort);
        PlayM4_CloseStream(m_nPort);
        PlayM4_FreePort(m_nPort);
        m_nPort = -1;
    }
    
    {
        std::lock_guard<std::mutex> lock(m_imageMutex);
        m_currentImage = QImage();
    }
    update();

    {
        std::lock_guard<std::mutex> lock(m_poolMutex);
        m_frameBufferPool.clear();
    }

    m_isPlaying = false;
    emit playingChanged();
}

QString HikvisionArchivePlayer::recorderIp() const { return m_recorderIp; }
void HikvisionArchivePlayer::setRecorderIp(const QString &ip) {
    if (m_recorderIp != ip) {
        cleanupPlayback();
        if (m_lUserID >= 0) {
            if (HikvisionManager::instance()) {
                HikvisionManager::instance()->logoutShared(m_recorderIp);
            } else {
                NET_DVR_Logout(m_lUserID);
            }
            m_lUserID = -1;
        }
        m_recorderIp = ip;
        emit recorderIpChanged();
    }
}

int HikvisionArchivePlayer::channelId() const { return m_channelId; }
void HikvisionArchivePlayer::setChannelId(int id) {
    if (m_channelId != id) {
        cleanupPlayback();
        m_channelId = id;
        emit channelIdChanged();
    }
}

int HikvisionArchivePlayer::port() const { return m_port; }
void HikvisionArchivePlayer::setPort(int p) {
    if (m_port != p) {
        cleanupPlayback();
        if (m_lUserID >= 0) {
            if (HikvisionManager::instance()) {
                HikvisionManager::instance()->logoutShared(m_recorderIp);
            } else {
                NET_DVR_Logout(m_lUserID);
            }
            m_lUserID = -1;
        }
        m_port = p;
        emit portChanged();
    }
}

QString HikvisionArchivePlayer::username() const { return m_username; }
void HikvisionArchivePlayer::setUsername(const QString &un) {
    if (m_username != un) {
        cleanupPlayback();
        if (m_lUserID >= 0) {
            if (HikvisionManager::instance()) {
                HikvisionManager::instance()->logoutShared(m_recorderIp);
            } else {
                NET_DVR_Logout(m_lUserID);
            }
            m_lUserID = -1;
        }
        m_username = un;
        emit usernameChanged();
    }
}

QString HikvisionArchivePlayer::password() const { return m_password; }
void HikvisionArchivePlayer::setPassword(const QString &pw) {
    if (m_password != pw) {
        cleanupPlayback();
        if (m_lUserID >= 0) {
            if (HikvisionManager::instance()) {
                HikvisionManager::instance()->logoutShared(m_recorderIp);
            } else {
                NET_DVR_Logout(m_lUserID);
            }
            m_lUserID = -1;
        }
        m_password = pw;
        emit passwordChanged();
    }
}

qint64 HikvisionArchivePlayer::currentPlayheadMs() const { return m_currentPlayheadMs; }
bool HikvisionArchivePlayer::isPlaying() const { return m_isPlaying; }

bool HikvisionArchivePlayer::ensureLogin()
{
    static bool s_sdkInit = false;
    if (!s_sdkInit) {
        NET_DVR_Init();
        s_sdkInit = true;
    }

    if (m_lUserID >= 0) return true;
    if (m_recorderIp.isEmpty()) {
        qWarning() << "[HikArchive] ensureLogin: recorderIp is EMPTY, cannot login";
        return false;
    }

    NET_DVR_DEVICEINFO_V40 deviceInfo;
    std::memset(&deviceInfo, 0, sizeof(NET_DVR_DEVICEINFO_V40));

    HikvisionManager* mgr = HikvisionManager::instance();
    if (mgr) {
        m_lUserID = mgr->loginShared(m_recorderIp, m_port, m_username, m_password, deviceInfo);
    } else {
        qWarning() << "[HikArchive] HikvisionManager instance is null, falling back to direct login!";
        NET_DVR_USER_LOGIN_INFO loginInfo;
        std::memset(&loginInfo, 0, sizeof(NET_DVR_USER_LOGIN_INFO));
        std::strncpy(loginInfo.sDeviceAddress, m_recorderIp.toUtf8().constData(), sizeof(loginInfo.sDeviceAddress) - 1);
        loginInfo.wPort = static_cast<WORD>(m_port);
        std::strncpy(loginInfo.sUserName, m_username.toUtf8().constData(), sizeof(loginInfo.sUserName) - 1);
        std::strncpy(loginInfo.sPassword, m_password.toUtf8().constData(), sizeof(loginInfo.sPassword) - 1);
        loginInfo.bUseAsynLogin = FALSE;
        loginInfo.byLoginMode = 0;

        m_lUserID = NET_DVR_Login_V40(&loginInfo, &deviceInfo);
    }

    if (m_lUserID < 0) {
        DWORD err = NET_DVR_GetLastError();
        qWarning() << "[HikArchive] Login FAILED for IP:" << m_recorderIp << "Error:" << err;
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

    qDebug() << "[HikArchive] Login SUCCESS. UserID:" << m_lUserID
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

    cleanupPlayback();

    if (!ensureLogin()) {
        qWarning() << "[HikArchive] Cannot play - login failed";
        return;
    }

    qDebug() << "[HikArchive] Requesting playback at" << dateTime << "on channel" << m_channelId;

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

    m_lPlayHandle = NET_DVR_PlayBackByTime(m_lUserID, m_realSdkChannel, &startTime, &stopTime, 0);
    if (m_lPlayHandle < 0) {
        DWORD err = NET_DVR_GetLastError();
        qWarning() << "[HikArchive] PlayBackByTime FAILED. Error:" << err << "Channel used:" << m_realSdkChannel;
        return;
    }
    qDebug() << "[HikArchive] PlayBackByTime SUCCESS. Handle:" << m_lPlayHandle;

    // Allocate a free port for decoding
    LONG tempPort = -1;
    if (!PlayM4_GetPort(&tempPort)) {
        qWarning() << "[HikArchive] PlayM4_GetPort FAILED.";
        return;
    }
    m_nPort = tempPort;
    qDebug() << "[HikArchive] PlayM4 port allocated:" << m_nPort;

    if (!PlayM4_SetStreamOpenMode(m_nPort, STREAME_FILE)) {
        qWarning() << "[HikArchive] PlayM4_SetStreamOpenMode FAILED.";
    }

    // Set network stream callback to pump data into the PlayM4 decoder
    if (!NET_DVR_SetPlayDataCallBack_V40(m_lPlayHandle, PlayDataCallBack, this)) {
        DWORD err = NET_DVR_GetLastError();
        qWarning() << "[HikArchive] SetPlayDataCallBack_V40 FAILED. Error:" << err;
        return;
    }
    qDebug() << "[HikArchive] PlayDataCallBack registered.";
    
    // Start playback control
    if (!NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYSTART, nullptr, 0, nullptr, nullptr)) {
        DWORD err = NET_DVR_GetLastError();
        qWarning() << "[HikArchive] NET_DVR_PLAYSTART FAILED. Error:" << err;
        return;
    }
    qDebug() << "[HikArchive] Playback STARTED successfully!";

    m_sysHeadReceived = false;
    m_isPlaying = true;
    emit playingChanged();
}

void HikvisionArchivePlayer::setPlaybackSpeed(int speedMultiplier)
{
    if (m_lPlayHandle < 0) return;

    qDebug() << "[HikArchive] setPlaybackSpeed:" << speedMultiplier;

    // 1. Reset NVR speed to normal (always 1x first to clear any FAST/SLOW states)
    if (!NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYNORMAL, nullptr, 0, nullptr, nullptr)) {
        qWarning() << "[HikArchive] setPlaybackSpeed NORMAL failed:" << NET_DVR_GetLastError();
    }

    // 2. Reset PlayM4 speed to normal
    if (m_nPort != -1) {
        PlayM4_Play(m_nPort, 0);
    }

    // 3. Set the direction on the NVR stream and PlayM4 decoder
    if (speedMultiplier < 0) {
        if (!NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAY_REVERSE, nullptr, 0, nullptr, nullptr)) {
            qWarning() << "[HikArchive] NET_DVR_PLAY_REVERSE failed:" << NET_DVR_GetLastError();
        }
        // Keep decoding forward! The NVR will reverse and stream the frames sequentially.
        if (m_nPort != -1) {
            if (!PlayM4_Play(m_nPort, 0)) {
                qWarning() << "[HikArchive] PlayM4_Play forward (for reverse) failed:" << PlayM4_GetLastError(m_nPort);
            }
        }
    } else {
        if (!NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAY_FORWARD, nullptr, 0, nullptr, nullptr)) {
            qWarning() << "[HikArchive] NET_DVR_PLAY_FORWARD failed:" << NET_DVR_GetLastError();
        }
        if (m_nPort != -1) {
            if (!PlayM4_Play(m_nPort, 0)) {
                qWarning() << "[HikArchive] PlayM4_Play forward failed:" << PlayM4_GetLastError(m_nPort);
            }
        }
    }

    // 4. Apply step-by-step fast commands if speed multiplier is > 1
    int absSpeed = std::abs(speedMultiplier);
    if (absSpeed > 1) {
        int steps = (absSpeed == 2) ? 1 : ((absSpeed == 4) ? 2 : 3);
        for (int i = 0; i < steps; ++i) {
            if (!NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYFAST, nullptr, 0, nullptr, nullptr)) {
                qWarning() << "[HikArchive] setPlaybackSpeed FAST step" << i << "failed:" << NET_DVR_GetLastError();
            }
            if (m_nPort != -1) {
                PlayM4_Fast(m_nPort);
            }
        }
    }
}

void HikvisionArchivePlayer::pause()
{
    if (m_lPlayHandle >= 0) {
        if (m_nPort != -1) PlayM4_Pause(m_nPort, 1);
        NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYPAUSE, nullptr, 0, nullptr, nullptr);
        m_isPlaying = false;
        emit playingChanged();
    }
}

void HikvisionArchivePlayer::resume()
{
    if (m_lPlayHandle >= 0) {
        if (m_nPort != -1) PlayM4_Pause(m_nPort, 0);
        NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYRESTART, nullptr, 0, nullptr, nullptr);
        NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYNORMAL, nullptr, 0, nullptr, nullptr);
        m_isPlaying = true;
        emit playingChanged();
    }
}

void HikvisionArchivePlayer::stop()
{
    qDebug() << "[HikArchive] stop() called from QML!";
    cleanupPlayback();
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

    auto* player = static_cast<HikvisionArchivePlayer*>(pUser);
    if (!player) {
        qWarning() << "[HikArchive] PlayDataCallBack: player is NULL!";
        return;
    }

    LONG activeHandle = player->m_lPlayHandle.load();
    if (lPlayHandle != activeHandle || activeHandle < 0) {
        // Discard late data from a previously stopped session to prevent stream/decoder corruption
        return;
    }

    LONG activePort = player->m_nPort.load();

    int count = ++s_dataCallbackCount;
    if (count <= 5 || count % 100 == 0) {
        qDebug() << "[HikArchive] PlayDataCallBack #" << count
                 << "type=" << dwDataType << "size=" << dwBufSize
                 << "port=" << activePort;
    }

    if (dwDataType == NET_DVR_SYSHEAD) {
        player->m_sysHeadReceived = true;
        qDebug() << "[HikArchive] Got SYSHEAD (stream header), size=" << dwBufSize;

        if (activePort < 0) {
            qWarning() << "[HikArchive] SYSHEAD received but activePort is invalid!";
            return;
        }

        if (!PlayM4_OpenStream(activePort, pBuffer, dwBufSize, 80 * 1024 * 1024)) {
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
        }
    } else if (dwDataType == NET_DVR_STREAMDATA) {
        if (!player->m_sysHeadReceived) {
            return; // Ignore late data from a previous stopped playback session
        }
        if (activePort < 0) {
            return;
        }
        int retryCount = 0;
        while (!PlayM4_InputData(activePort, pBuffer, dwBufSize)) {
            if (player->m_lPlayHandle.load() != activeHandle || player->m_nPort.load() != activePort || !player->m_isPlaying) {
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

    if (info->nType == T_YV12) {
        int width = info->nWidth;
        int height = info->nHeight;
        
        if (width <= 0 || height <= 0 || nSize < width * height * 3 / 2) {
            qWarning() << "[HikArchive] DecCallBack: invalid frame dimensions w=" << width << "h=" << height << "size=" << nSize;
            return;
        }

        if (player->m_pendingTasks.load() >= 5) {
            // Drop frame to prevent thread pools/queues from filling up
            return;
        }
        
        std::shared_ptr<FrameBuffer> fb = player->getOrCreateFrameBuffer(width, height);
        if (!fb) return;

        // Copy raw YV12 data to the frame buffer
        std::memcpy(fb->yv12Data.data(), pBuf, nSize);

        player->m_pendingTasks++;

        auto* task = new YV12ToRGBTask(player, fb, player->m_lPlayHandle.load());
        QThreadPool::globalInstance()->start(task);
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
        painter->drawText(boundingRect(), Qt::AlignCenter, "Ładowanie archiwum Hikvision...");
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

