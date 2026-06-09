#include "hikvisionarchiveplayer.h"
#include "hikvisionmanager.h"
#include "qmlav/src/qmlavdemuxer.h"
#include <QPainter>
#include <QDebug>
#include <QCoreApplication>
#include <QThreadPool>
#include <QRunnable>
#include <iostream>
#include <thread>
#include <chrono>

// Hikvision PlayM4 decoder constants (usually YV12)
#define T_YV12 3

#include <fstream>
#include <iomanip>
#include <mutex>

static void logToFile(const std::string& /*message*/) {
    // Disabled for production release
}




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

    m_stopPacing = true;
    m_pacingInitialized = false;
    m_lastStamp.store(0);
    m_zeroStampCount.store(0);
    m_sysHeadReceived.store(false);

    m_runPresentation = false;
    m_queueCond.notify_all();
    if (m_presentationThread.joinable()) {
        m_presentationThread.join();
    }

    {
        std::lock_guard<std::mutex> lock(m_queueMutex);
        m_frameQueue.clear();
    }

    // Wait for any active display callbacks to finish (they will exit quickly as m_stopPacing is true)
    while (m_activeDisplayCallbacks.load() > 0) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    m_currentNvrSpeed.store(1);

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

    logToFile("[HikArchive] playAtTime called with: " + dateTime.toString("yyyy-MM-dd hh:mm:ss").toStdString() + ", recorderIp=" + m_recorderIp.toStdString() + ", logical channelId=" + std::to_string(m_channelId));

    cleanupPlayback();
    m_stopPacing = false;

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

    m_runPresentation = true;
    m_presentationThread = std::thread(&HikvisionArchivePlayer::presentationLoop, this);

    emit playingChanged();
}

void HikvisionArchivePlayer::setPlaybackSpeed(int speedMultiplier)
{
    qDebug() << "[HikArchive] setPlaybackSpeed requested:" << speedMultiplier;
    logToFile("[HikArchive] setPlaybackSpeed requested: " + std::to_string(speedMultiplier));
    m_playbackSpeed.store(speedMultiplier);
    m_pacingInitialized = false;
    m_lastStamp.store(0);
    m_zeroStampCount.store(0);

    {
        std::lock_guard<std::mutex> lock(m_queueMutex);
        m_frameQueue.clear();
    }

    applyPlaybackSpeed();
}

void HikvisionArchivePlayer::applyPlaybackSpeed()
{
    if (m_lPlayHandle < 0) return;

    int speedMultiplier = m_playbackSpeed.load();

    // If port isn't opened and syshead isn't received, we cannot apply speed to PlayM4 yet.
    // We defer applying it until SYSHEAD callback arrives.
    if (m_nPort < 0 || !m_sysHeadReceived.load()) {
        qDebug() << "[HikArchive] applyPlaybackSpeed deferred: port =" << m_nPort << "syshead =" << m_sysHeadReceived.load();
        return;
    }

    qDebug() << "[HikArchive] applyPlaybackSpeed executing: speed =" << speedMultiplier << "port =" << m_nPort;

    // CRITICAL: If both desired and currently applied speeds are 1, completely skip sending any NVR controls.
    // This preserves default paced streaming at startup/restart on picky NVRs (like Recorder 07).
    if (speedMultiplier == 1 && m_currentNvrSpeed.load() == 1) {
        PlayM4_Play(m_nPort, 0);
        qDebug() << "[HikArchive] applyPlaybackSpeed: already in paced 1x state, skipping NVR controls";
        return;
    }

    // 1. Reset NVR speed to normal (always 1x first to clear any FAST/SLOW states)
    if (!NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYNORMAL, nullptr, 0, nullptr, nullptr)) {
        qWarning() << "[HikArchive] applyPlaybackSpeed NORMAL failed:" << NET_DVR_GetLastError();
    }

    // 2. Reset PlayM4 speed to normal
    PlayM4_Play(m_nPort, 0);

    // CRITICAL FIX: If speed is 1x, do NOT send NET_DVR_PLAY_FORWARD as it disables pacing on some NVRs!
    if (speedMultiplier == 1) {
        qDebug() << "[HikArchive] applyPlaybackSpeed: speed is 1x, early exit to keep paced stream";
        m_currentNvrSpeed.store(1);
        return;
    }

    // 3. Set the direction on the NVR stream and PlayM4 decoder
    if (speedMultiplier < 0) {
        if (!NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAY_REVERSE, nullptr, 0, nullptr, nullptr)) {
            qWarning() << "[HikArchive] NET_DVR_PLAY_REVERSE failed:" << NET_DVR_GetLastError();
        }
        // Keep decoding forward! The NVR will reverse and stream the frames sequentially.
        if (!PlayM4_Play(m_nPort, 0)) {
            qWarning() << "[HikArchive] PlayM4_Play forward (for reverse) failed:" << PlayM4_GetLastError(m_nPort);
        }
    } else {
        if (!NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAY_FORWARD, nullptr, 0, nullptr, nullptr)) {
            qWarning() << "[HikArchive] NET_DVR_PLAY_FORWARD failed:" << NET_DVR_GetLastError();
        }
        if (!PlayM4_Play(m_nPort, 0)) {
            qWarning() << "[HikArchive] PlayM4_Play forward failed:" << PlayM4_GetLastError(m_nPort);
        }
    }

    // 4. Apply step-by-step fast commands if speed multiplier is > 1
    int absSpeed = std::abs(speedMultiplier);
    if (absSpeed > 1) {
        int steps = (absSpeed == 2) ? 1 : ((absSpeed == 4) ? 2 : 3);
        for (int i = 0; i < steps; ++i) {
            if (!NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYFAST, nullptr, 0, nullptr, nullptr)) {
                qWarning() << "[HikArchive] applyPlaybackSpeed FAST step" << i << "failed:" << NET_DVR_GetLastError();
            }
            PlayM4_Fast(m_nPort);
        }
    }

    m_currentNvrSpeed.store(speedMultiplier);
}


void HikvisionArchivePlayer::pause()
{
    if (m_lPlayHandle >= 0) {
        if (m_nPort != -1) PlayM4_Pause(m_nPort, 1);
        NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYPAUSE, nullptr, 0, nullptr, nullptr);
        m_isPlaying = false;
        m_pacingInitialized = false;

        {
            std::lock_guard<std::mutex> lock(m_queueMutex);
            m_frameQueue.clear();
        }

        emit playingChanged();
    }
}

void HikvisionArchivePlayer::resume()
{
    if (m_lPlayHandle >= 0) {
        if (m_nPort != -1) PlayM4_Pause(m_nPort, 0);
        NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYRESTART, nullptr, 0, nullptr, nullptr);
        
        // Avoid sending PLAYNORMAL to NVR if we are already in normal paced 1x speed mode
        if (m_currentNvrSpeed.load() != 1) {
            NET_DVR_PlayBackControl_V40(m_lPlayHandle, NET_DVR_PLAYNORMAL, nullptr, 0, nullptr, nullptr);
            m_currentNvrSpeed.store(1);
        }
        
        m_isPlaying = true;
        m_pacingInitialized = false;
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
    if (static_cast<int32_t>(lPlayHandle) != static_cast<int32_t>(activeHandle) || activeHandle < 0) {
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
        if (player->m_sysHeadReceived.load()) {
            // Subsequent SYSHEAD (e.g. from segment boundaries on NVR 07).
            // Do NOT re-open the stream or re-apply playback speed as it bombards the NVR.
            // Just input the header bytes directly into the PlayM4 decoder.
            if (activePort >= 0) {
                PlayM4_InputData(activePort, pBuffer, dwBufSize);
            }
            return;
        }

        player->m_sysHeadReceived = true;
        qDebug() << "[HikArchive] Got FIRST SYSHEAD (stream header), size=" << dwBufSize;
        logToFile("[HikArchive] PlayDataCallBack got FIRST SYSHEAD, size=" + std::to_string(dwBufSize) + ", port=" + std::to_string(activePort));

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

        if (!PlayM4_SetDisplayCallBack(activePort, DisplayCallBack)) {
            DWORD playErr = PlayM4_GetLastError(activePort);
            qWarning() << "[HikArchive] PlayM4_SetDisplayCallBack FAILED. PlayM4 error:" << playErr;
        } else {
            qDebug() << "[HikArchive] PlayM4_SetDisplayCallBack OK";
        }
        
        if (!PlayM4_Play(activePort, 0)) {
            DWORD playErr = PlayM4_GetLastError(activePort);
            qWarning() << "[HikArchive] PlayM4_Play FAILED. PlayM4 error:" << playErr;
        } else {
            qDebug() << "[HikArchive] PlayM4_Play OK - decoder started!";
            player->applyPlaybackSpeed();
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
                    static int bufOverLogCount = 0;
                    if (bufOverLogCount < 10000) {
                        bufOverLogCount++;
                        logToFile("[HikArchive] PlayM4_InputData buffer full (PLAYM4_BUF_OVER) on port " + std::to_string(activePort) + ", retried " + std::to_string(retryCount) + " times.");
                    }
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

void HikvisionArchivePlayer::DisplayCallBack(long nPort, char *pBuf, long nSize, long nWidth, long nHeight, long nStamp, long nType, long nReserved)
{
    Q_UNUSED(nReserved);

    int32_t cleanPort = static_cast<int32_t>(nPort);
    int32_t size = static_cast<int32_t>(nSize);
    int32_t width = static_cast<int32_t>(nWidth);
    int32_t height = static_cast<int32_t>(nHeight);
    int32_t stamp = static_cast<int32_t>(nStamp);
    int32_t type = static_cast<int32_t>(nType);

    HikvisionArchivePlayer* player = nullptr;
    {
        std::lock_guard<std::mutex> lock(s_portMapMutex);
        auto it = s_portMap.find(cleanPort);
        if (it != s_portMap.end()) {
            player = it->second;
        }
    }

    if (!player) return;

    // RAII guard to safely track active callbacks so cleanupPlayback/destructor can wait for them to exit
    struct CallbackGuard {
        HikvisionArchivePlayer* p;
        CallbackGuard(HikvisionArchivePlayer* player) : p(player) {
            p->m_activeDisplayCallbacks++;
        }
        ~CallbackGuard() {
            p->m_activeDisplayCallbacks--;
        }
    };
    CallbackGuard guard(player);

    if (player->m_stopPacing.load()) {
        return;
    }

    int count = ++s_decCallbackCount;
    if (count <= 3 || count % 100 == 0) {
        qDebug() << "[HikArchive] DisplayCallBack #" << count
                 << "type=" << type
                 << "size=" << size
                 << "w=" << width
                 << "h=" << height
                 << "stamp=" << stamp;
    }

    if (type == T_YV12) {
        if (width <= 0 || height <= 0 || size < width * height * 3 / 2) {
            qWarning() << "[HikArchive] DisplayCallBack: invalid frame dimensions w=" << width << "h=" << height << "size=" << size;
            return;
        }

        // Enforce healthy queue backpressure: if queue has >= 30 frames, sleep for 5ms inside DisplayCallBack
        // to slow down the PlayM4 decoder thread, but don't stall completely.
        int backpressureSleeps = 0;
        while (true) {
            if (player->m_stopPacing.load()) {
                return;
            }
            size_t queueSize = 0;
            {
                std::lock_guard<std::mutex> lock(player->m_queueMutex);
                queueSize = player->m_frameQueue.size();
            }
            if (queueSize < 30) {
                break;
            }
            std::this_thread::sleep_for(std::chrono::milliseconds(5));
            backpressureSleeps++;
        }
        if (backpressureSleeps > 0) {
            static int bpLogCount = 0;
            if (bpLogCount < 10000) {
                bpLogCount++;
                logToFile("[HikArchive] DisplayCallBack backpressure throttled decoder thread (slept " + std::to_string(backpressureSleeps * 5) + "ms, queue size >= 30).");
            }
        }

        // Copy raw YV12 data to a QueueFrame and push it to the queue
        QueueFrame qf;
        try {
            qf.yv12Data.assign(pBuf, pBuf + size);
        } catch (const std::exception& e) {
            qWarning() << "[HikArchive] Failed to allocate QueueFrame memory:" << e.what();
            return;
        }
        qf.width = width;
        qf.height = height;
        qf.stamp = stamp;

        {
            std::lock_guard<std::mutex> lock(player->m_queueMutex);
            player->m_frameQueue.push_back(std::move(qf));
        }
        player->m_queueCond.notify_one();
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

bool HikvisionArchivePlayer::saveCurrentFrame(const QString &path) const
{
    std::lock_guard<std::mutex> lock(m_imageMutex);
    if (m_currentImage.isNull()) {
        return false;
    }
    return m_currentImage.save(path, "JPG", 98);
}

void HikvisionArchivePlayer::presentationLoop()
{
    qDebug() << "[HikArchive] Presentation thread started";
    logToFile("[HikArchive] Presentation thread started");

    int frameCount = 0;
    long long totalStampDelta = 0;
    int anomalyCount = 0;
    int fallbackCount = 0;
    double totalSleepMs = 0.0;
    size_t maxQueueSizeSeen = 0;

    while (m_runPresentation.load()) {
        QueueFrame frame;
        {
            std::unique_lock<std::mutex> lock(m_queueMutex);
            m_queueCond.wait(lock, [this]() {
                return !m_runPresentation.load() || !m_frameQueue.empty();
            });
            if (!m_runPresentation.load()) {
                break;
            }
            if (m_frameQueue.empty()) {
                continue;
            }
            frame = std::move(m_frameQueue.front());
            m_frameQueue.erase(m_frameQueue.begin());
        }

        if (m_stopPacing.load()) {
            continue;
        }

        // --- PACING LOGIC ON PRESENTATION THREAD ---
        long stamp = frame.stamp;
        long stampDelta = 0;
        bool isFlat = false;

        if (stamp == 0) {
            isFlat = true;
        } else if (m_pacingInitialized.load()) {
            long lastStamp = m_lastStamp.load();
            stampDelta = stamp - lastStamp;
            if (stampDelta >= 0 && stampDelta < 15) {
                isFlat = true;
            }
        }

        if (isFlat) {
            m_zeroStampCount++;
        } else {
            if (m_zeroStampCount.load() > 10) {
                // Transitioning from Steady Fallback back to normal mode:
                // Reset pacing initialization so normal mode can re-calibrate.
                m_pacingInitialized.store(false);
                logToFile("[HikArchive] Pacing transitioning from Steady Fallback back to normal mode.");
            }
            m_zeroStampCount.store(0);
        }

        bool useSteadyFallback = (m_zeroStampCount.load() > 10);
        double interval_ms = 40.0; // Default fallback to 25 fps

        if (useSteadyFallback) {
            interval_ms = 40.0;
            fallbackCount++;
        } else {
            if (!m_pacingInitialized.load()) {
                m_pacingStartTime = std::chrono::steady_clock::now();
                m_pacingStartStamp.store(stamp);
                m_lastStamp.store(stamp);
                m_lastFrameRealTime = m_pacingStartTime;
                m_pacingInitialized.store(true);
                interval_ms = 0.0; // Display first frame immediately
                logToFile("[HikArchive] Pacing initialized. Start stamp: " + std::to_string(stamp));
            } else {
                long lastStamp = m_lastStamp.load();
                stampDelta = stamp - lastStamp;

                // Handle timestamp discontinuity (gap or seek)
                if (stampDelta > 2000) {
                    m_pacingStartTime = std::chrono::steady_clock::now();
                    m_pacingStartStamp.store(stamp);
                    m_lastFrameRealTime = m_pacingStartTime;
                    interval_ms = 0.0; // Display immediately
                    anomalyCount++;
                    logToFile("[HikArchive] Major gap detected (stampDelta: " + std::to_string(stampDelta) + "). Pacing reset. New stamp: " + std::to_string(stamp));
                } else if (stampDelta < 0) {
                    // Jitter / B-Frame: Do NOT reset pacing baseline!
                    // Just use 40ms interval and keep playing from the existing baseline.
                    interval_ms = 40.0;
                    anomalyCount++;
                    
                    static int jitterLogCount = 0;
                    if (jitterLogCount < 10000) {
                        jitterLogCount++;
                        logToFile("[HikArchive] Negative jitter detected (stampDelta: " + std::to_string(stampDelta) + ", stamp: " + std::to_string(stamp) + ", lastStamp: " + std::to_string(lastStamp) + "). Kept baseline, using 40ms fallback.");
                    }
                } else if (stampDelta == 0) {
                    interval_ms = 5.0; // Small delay to avoid hot-looping
                } else {
                    interval_ms = static_cast<double>(stampDelta);
                    totalStampDelta += stampDelta;
                }
            }
        }
        m_lastStamp.store(stamp);

        double speed = std::abs(m_playbackSpeed.load());
        if (speed <= 0) speed = 1.0;

        // Apply speed multiplier
        interval_ms /= speed;

        auto now = std::chrono::steady_clock::now();
        auto targetRealTime = m_lastFrameRealTime + std::chrono::milliseconds(static_cast<long long>(interval_ms));
        double sleep_ms = std::chrono::duration<double, std::milli>(targetRealTime - now).count();

        if (sleep_ms > 2000.0) {
            // Safety guard: if drift is too large, reset tracking to now
            m_pacingStartTime = now;
            m_lastFrameRealTime = now;
            logToFile("[HikArchive] Sleep drift too large (sleep_ms: " + std::to_string(sleep_ms) + "). Reset baseline.");
        } else if (sleep_ms > 0.0) {
            double remaining_ms = sleep_ms;
            while (remaining_ms > 0.0) {
                if (!m_runPresentation.load() || m_stopPacing.load()) {
                    break;
                }
                double chunk = std::min(remaining_ms, 5.0);
                std::this_thread::sleep_for(std::chrono::milliseconds(static_cast<long long>(chunk)));
                remaining_ms -= chunk;
            }
            m_lastFrameRealTime = targetRealTime;
            totalSleepMs += sleep_ms;
        } else {
            // Behind schedule (rendering/decoding was slow or backlog processing). Align baseline to now.
            m_lastFrameRealTime = now;
        }

        if (!m_runPresentation.load() || m_stopPacing.load()) {
            continue;
        }

        int width = frame.width;
        int height = frame.height;
        if (width <= 0 || height <= 0) {
            continue;
        }

        std::shared_ptr<FrameBuffer> fb = getOrCreateFrameBuffer(width, height);
        if (!fb) {
            continue;
        }

        const unsigned char* yPlane = frame.yv12Data.data();
        const unsigned char* vPlane = yPlane + width * height;
        const unsigned char* uPlane = vPlane + (width * height) / 4;

        unsigned char* destData = fb->rgbData.data();
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

        // Wrap RGB buffer in a QImage
        auto* pShared = new std::shared_ptr<FrameBuffer>(fb);
        QImage img(fb->rgbData.data(), width, height, destStride, QImage::Format_RGB32, [](void* info) {
            auto* pShared = static_cast<std::shared_ptr<FrameBuffer>*>(info);
            if (pShared) {
                (*pShared)->inUse = false;
                delete pShared;
            }
        }, pShared);

        LONG activeHandle = m_lPlayHandle.load();
        QMetaObject::invokeMethod(this, [this, img, activeHandle]() {
            if (m_lPlayHandle.load() == activeHandle) {
                updateImage(img);
            }
        }, Qt::QueuedConnection);

        // Stats aggregation
        frameCount++;
        size_t currentQueueSize = 0;
        {
            std::lock_guard<std::mutex> lock(m_queueMutex);
            currentQueueSize = m_frameQueue.size();
        }
        if (currentQueueSize > maxQueueSizeSeen) {
            maxQueueSizeSeen = currentQueueSize;
        }

        if (frameCount >= 100) {
            double avgStampDelta = frameCount > 0 ? (double)totalStampDelta / frameCount : 0.0;
            std::string logMsg = "[HikArchive] Presentation loop stats (100 frames): avg stampDelta=" + std::to_string(avgStampDelta) 
                + "ms, anomalies=" + std::to_string(anomalyCount) 
                + ", fallbackCount=" + std::to_string(fallbackCount)
                + ", avgSleep=" + std::to_string(totalSleepMs / frameCount)
                + "ms, maxQueueSize=" + std::to_string(maxQueueSizeSeen)
                + ", speedMultiplier=" + std::to_string(m_playbackSpeed.load());
            logToFile(logMsg);
            
            // Reset stats
            frameCount = 0;
            totalStampDelta = 0;
            anomalyCount = 0;
            fallbackCount = 0;
            totalSleepMs = 0.0;
            maxQueueSizeSeen = currentQueueSize;
        }
    }
    qDebug() << "[HikArchive] Presentation thread stopped";
    logToFile("[HikArchive] Presentation thread stopped");
}

