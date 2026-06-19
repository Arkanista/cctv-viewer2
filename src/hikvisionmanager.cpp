#include "hikvisionmanager.h"
#include "context.h"
#include <QDebug>
#include <QProcess>
#include <QRegularExpression>
#include <QRegularExpressionMatchIterator>
#include <QThread>

HikvisionManager* HikvisionManager::m_instance = nullptr;

HikvisionManager::HikvisionManager(QObject *parent)
    : QObject(parent)
    , m_initialized(false)
{
    m_instance = this;

    std::thread initThread([this]() {
        if (NET_DVR_Init()) {
            m_initialized = true;
            qDebug() << "[Hikvision] HCNetSDK Initialized successfully in background.";
        } else {
            qWarning() << "[Hikvision] Failed to initialize HCNetSDK.";
        }
        {
            std::lock_guard<std::mutex> lock(m_initMutex);
            m_initCompleted = true;
        }
        m_initCond.notify_all();
    });
    initThread.detach();

    // Start background worker thread for PTZ commands
    m_ptzWorker = std::thread(&HikvisionManager::ptzWorkerLoop, this);
}

HikvisionManager::~HikvisionManager()
{
    // Stop the worker thread cleanly first
    {
        std::lock_guard<std::mutex> lock(m_ptzMutex);
        m_ptzWorkerStop = true;
    }
    m_ptzCond.notify_all();
    if (m_ptzWorker.joinable()) {
        m_ptzWorker.join();
    }

    ensureInitialized();

    // Logout all active sessions
    for (auto it = m_sessions.begin(); it != m_sessions.end(); ++it) {
        NET_DVR_Logout(it.value().lUserID);
    }
    m_sessions.clear();

    for (auto it = m_sharedSessions.begin(); it != m_sharedSessions.end(); ++it) {
        NET_DVR_Logout(it.value().lUserID);
    }
    m_sharedSessions.clear();

    if (m_initialized) {
        NET_DVR_Cleanup();
        qDebug() << "[Hikvision] HCNetSDK Cleaned up.";
    }
    m_instance = nullptr;
}

HikvisionManager* HikvisionManager::instance()
{
    return m_instance;
}

static QByteArray fetchUrl(const QString &ip, int port, const QString &username, const QString &password, const QString &path) {
    QProcess process;
    QStringList args;
    args << "-s" << "--digest" << "-u" << QString("%1:%2").arg(username, password)
         << "--max-time" << "4"
         << QString("http://%1:%2%3").arg(ip).arg(port).arg(path);
    
    qDebug() << "[Hikvision ISAPI] Querying:" << args.last();
    process.start("curl", args);
    if (process.waitForFinished(5000)) {
        return process.readAllStandardOutput();
    }
    return QByteArray();
}

QVariantList HikvisionManager::discoverCameras(const QString &ip, int port, const QString &username, const QString &password)
{
    QVariantList cameraList;

    // Try ISAPI HTTP discovery first to support real NVRs/DVRs
    int httpPort = port;
    if (port == 8000) {
        httpPort = 80; // Default HTTP port when SDK port is specified
    }

    qDebug() << "[Hikvision] Attempting real NVR HTTP ISAPI discovery on" << ip << "port" << httpPort;
    QByteArray xmlAnalog = fetchUrl(ip, httpPort, username, password, "/ISAPI/System/Video/inputs/channels");
    if (xmlAnalog.isEmpty() && httpPort != 80) {
        xmlAnalog = fetchUrl(ip, 80, username, password, "/ISAPI/System/Video/inputs/channels");
        if (!xmlAnalog.isEmpty()) {
            httpPort = 80;
        }
    }

    if (!xmlAnalog.isEmpty()) {
        qDebug() << "[Hikvision] ISAPI discovery succeeded! Parsing channels...";
        // Parse active analog/TVI channels
        QRegularExpression rxChan("<VideoInputChannel[^>]*>([\\s\\S]*?)</VideoInputChannel>");
        QRegularExpressionMatchIterator iChan = rxChan.globalMatch(QString::fromUtf8(xmlAnalog));
        while (iChan.hasNext()) {
            QRegularExpressionMatch match = iChan.next();
            QString channelXml = match.captured(1);
            
            QRegularExpression rxId("<id>(\\d+)</id>");
            QRegularExpression rxName("<name>(.*?)</name>");
            QRegularExpression rxEnabled("<videoInputEnabled>(.*?)</videoInputEnabled>");
            
            int id = rxId.match(channelXml).captured(1).toInt();
            QString name = rxName.match(channelXml).captured(1);
            QString enabled = rxEnabled.match(channelXml).captured(1);
            
            if (id > 0 && enabled != "false") {
                QVariantMap cam;
                cam.insert("channelId", id);
                cam.insert("name", name.isEmpty() ? QString("Camera %1").arg(id) : name);
                cam.insert("recorderIp", ip);
                cameraList.append(cam);
                qDebug() << "[Hikvision ISAPI] Discovered active analog channel:" << id << "name:" << name;
            }
        }

        // Parse IP/Proxy channels
        QByteArray xmlIP = fetchUrl(ip, httpPort, username, password, "/ISAPI/ContentMgmt/InputProxy/channels");
        if (!xmlIP.isEmpty()) {
            QRegularExpression rxIP("<InputProxyChannel[^>]*>([\\s\\S]*?)</InputProxyChannel>");
            QRegularExpressionMatchIterator iIP = rxIP.globalMatch(QString::fromUtf8(xmlIP));
            while (iIP.hasNext()) {
                QRegularExpressionMatch match = iIP.next();
                QString channelXml = match.captured(1);
                
                QRegularExpression rxId("<id>(\\d+)</id>");
                QRegularExpression rxName("<name>(.*?)</name>");
                
                int id = rxId.match(channelXml).captured(1).toInt();
                QString name = rxName.match(channelXml).captured(1);
                
                if (id > 0) {
                    QVariantMap cam;
                    cam.insert("channelId", id);
                    cam.insert("name", name.isEmpty() ? QString("Camera %1").arg(id) : name);
                    cam.insert("recorderIp", ip);
                    cameraList.append(cam);
                    qDebug() << "[Hikvision ISAPI] Discovered proxy IP channel:" << id << "name:" << name;
                }
            }
        }

        if (!cameraList.isEmpty()) {
            return cameraList;
        }
    }

    qDebug() << "[Hikvision] Real NVR HTTP ISAPI discovery returned no channels. Falling back to SDK/Mock...";

    if (!m_initialized) {
        qWarning() << "[Hikvision] Cannot login: SDK not initialized.";
        return cameraList;
    }

    // Logout from previous session on same IP if any
    logout(ip);

    NET_DVR_USER_LOGIN_INFO loginInfo;
    std::memset(&loginInfo, 0, sizeof(NET_DVR_USER_LOGIN_INFO));
    
    std::strncpy(loginInfo.sDeviceAddress, ip.toUtf8().constData(), sizeof(loginInfo.sDeviceAddress) - 1);
    loginInfo.wPort = static_cast<WORD>(port);
    std::strncpy(loginInfo.sUserName, username.toUtf8().constData(), sizeof(loginInfo.sUserName) - 1);
    std::strncpy(loginInfo.sPassword, password.toUtf8().constData(), sizeof(loginInfo.sPassword) - 1);
    loginInfo.bUseAsynLogin = FALSE;
    loginInfo.byLoginMode = 0; // Private mode

    NET_DVR_DEVICEINFO_V40 deviceInfo;
    std::memset(&deviceInfo, 0, sizeof(NET_DVR_DEVICEINFO_V40));

    LONG lUserID = NET_DVR_Login_V40(&loginInfo, &deviceInfo);
    if (lUserID < 0) {
        qWarning() << "[Hikvision] Login failed for IP:" << ip;
        return cameraList;
    }

    bool wasLogged = false;
    bool isLoggedNow = false;
    {
        std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);
        wasLogged = isLoggedInternal(ip);
        m_sessions.insert(ip, {lUserID, deviceInfo});
        isLoggedNow = isLoggedInternal(ip);
    }
    qDebug() << "[Hikvision] Logged in successfully to IP:" << ip << "with UserID:" << lUserID;
    if (wasLogged != isLoggedNow) {
        emit sessionStatusChanged(ip, isLoggedNow);
    }

    // Discover real cameras via NET_DVR_GET_IPPARACFG_V40
    NET_DVR_IPPARACFG_V40 ipParaCfg;
    std::memset(&ipParaCfg, 0, sizeof(NET_DVR_IPPARACFG_V40));
    DWORD bytesReturned = 0;
    
    BOOL getCfgRet = NET_DVR_GetDVRConfig(lUserID, NET_DVR_GET_IPPARACFG_V40, 0, &ipParaCfg, sizeof(NET_DVR_IPPARACFG_V40), &bytesReturned);
    
    if (getCfgRet) {
        DWORD startDChan = ipParaCfg.dwStartDChan;
        DWORD ipChanNum = ipParaCfg.dwDChanNum;
        if (ipChanNum == 0) ipChanNum = 64; // Max support
        
        for (DWORD i = 0; i < ipChanNum; ++i) {
            if (ipParaCfg.struIPDevInfo[i].byEnable == 1) {
                int chanId = static_cast<int>(startDChan + i);
                QVariantMap cam;
                cam.insert("channelId", chanId);
                cam.insert("name", QString("Camera %1").arg(i + 1));
                cam.insert("recorderIp", ip);
                cameraList.append(cam);
                qDebug() << "[Hikvision] Discovered active IP camera on channel:" << chanId;
            }
        }
    }
    
    // Fallback if no active IP cameras found or config query failed
    if (cameraList.isEmpty()) {
        int startChan = deviceInfo.struDeviceV30.byStartChan;
        int numChan = deviceInfo.struDeviceV30.byIPChanNum;
        
        if (numChan == 0) {
            startChan = deviceInfo.struDeviceV30.byStartChan;
            numChan = deviceInfo.struDeviceV30.byChanNum;
        }
 
        if (numChan == 0) {
            numChan = 4;
            startChan = 1;
        }

        for (int i = 0; i < numChan; ++i) {
            int chanId = startChan + i;
            QVariantMap cam;
            cam.insert("channelId", chanId);
            cam.insert("name", QString("Camera %1").arg(i + 1));
            cam.insert("recorderIp", ip);
            cameraList.append(cam);
        }
    }

    return cameraList;
}

void HikvisionManager::discoverCamerasAsync(const QString &ip, int port, const QString &username, const QString &password)
{
    QThread *thread = QThread::create([this, ip, port, username, password]() {
        QVariantList cameras = discoverCameras(ip, port, username, password);
        bool success = !cameras.isEmpty();
        QString errorMsg = success ? "" : tr("Login failed or no cameras discovered.");
        emit discoveryFinished(ip, cameras, success, errorMsg);
    });
    connect(thread, &QThread::finished, thread, &QThread::deleteLater);
    thread->start();
}

void HikvisionManager::logout(const QString &ip)
{
    LONG lUserID = -1;
    bool wasLogged = false;
    bool isLoggedNow = false;
    {
        std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);
        wasLogged = isLoggedInternal(ip);
        if (m_sessions.contains(ip)) {
            lUserID = m_sessions.take(ip).lUserID;
        }
        isLoggedNow = isLoggedInternal(ip);
    }
    if (lUserID >= 0) {
        ensureInitialized();
        NET_DVR_Logout(lUserID);
        qDebug() << "[Hikvision] Logged out from IP:" << ip << "UserID:" << lUserID;
    }
    if (wasLogged != isLoggedNow) {
        emit sessionStatusChanged(ip, isLoggedNow);
    }
}

bool HikvisionManager::isLogged(const QString &ip)
{
    std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);
    return isLoggedInternal(ip);
}

bool HikvisionManager::isLoggedInternal(const QString &ip) const
{
    return m_sessions.contains(ip) || m_sharedSessions.contains(ip);
}

bool HikvisionManager::getDeviceInfo(const QString &ip, NET_DVR_DEVICEINFO_V40 &deviceInfo)
{
    std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);
    if (m_sessions.contains(ip)) {
        deviceInfo = m_sessions.value(ip).deviceInfo;
        return true;
    }
    if (m_sharedSessions.contains(ip)) {
        deviceInfo = m_sharedSessions.value(ip).deviceInfo;
        return true;
    }
    return false;
}

LONG HikvisionManager::getSession(const QString &ip, int port, const QString &username, const QString &password)
{
    bool wasLogged = false;
    bool isLoggedNow = false;

    // 1. Check if already logged in
    {
        std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);
        if (m_sessions.contains(ip)) {
            return m_sessions.value(ip).lUserID;
        }
        if (m_sharedSessions.contains(ip)) {
            return m_sharedSessions.value(ip).lUserID;
        }
        wasLogged = isLoggedInternal(ip);
    }

    // 2. Not logged in, log in
    ensureInitialized();

    if (!m_initialized) {
        qWarning() << "[Hikvision] Cannot get session: SDK not initialized.";
        return -1;
    }

    NET_DVR_USER_LOGIN_INFO loginInfo;
    std::memset(&loginInfo, 0, sizeof(NET_DVR_USER_LOGIN_INFO));
    std::strncpy(loginInfo.sDeviceAddress, ip.toUtf8().constData(), sizeof(loginInfo.sDeviceAddress) - 1);
    loginInfo.wPort = static_cast<WORD>(port);
    std::strncpy(loginInfo.sUserName, username.toUtf8().constData(), sizeof(loginInfo.sUserName) - 1);
    std::strncpy(loginInfo.sPassword, password.toUtf8().constData(), sizeof(loginInfo.sPassword) - 1);
    loginInfo.bUseAsynLogin = FALSE;
    loginInfo.byLoginMode = 0; // Private mode

    NET_DVR_DEVICEINFO_V40 deviceInfo;
    std::memset(&deviceInfo, 0, sizeof(NET_DVR_DEVICEINFO_V40));

    LONG lUserID = NET_DVR_Login_V40(&loginInfo, &deviceInfo);
    if (lUserID < 0) {
        DWORD err = NET_DVR_GetLastError();
        qWarning() << "[Hikvision] getSession login FAILED for IP:" << ip << "Error:" << err;
        return -1;
    }

    {
        std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);
        m_sessions.insert(ip, {lUserID, deviceInfo});
        isLoggedNow = isLoggedInternal(ip);
    }

    qDebug() << "[Hikvision] getSession login SUCCESS for IP:" << ip << "UserID:" << lUserID;
    if (wasLogged != isLoggedNow) {
        emit sessionStatusChanged(ip, isLoggedNow);
    }

    return lUserID;
}

bool HikvisionManager::ptzZoom(const QString &ip, int port, const QString &username, const QString &password, int channelId, int command, bool stop)
{
    {
        std::lock_guard<std::mutex> lock(m_ptzMutex);
        m_ptzQueue.push({ip, port, username, password, channelId, command, stop});
    }
    m_ptzCond.notify_one();
    return true;
}

void HikvisionManager::ptzWorkerLoop()
{
    while (true) {
        PtzCommand cmd;
        {
            std::unique_lock<std::mutex> lock(m_ptzMutex);
            m_ptzCond.wait(lock, [this]() { return m_ptzWorkerStop || !m_ptzQueue.empty(); });
            if (m_ptzWorkerStop && m_ptzQueue.empty()) {
                break;
            }
            cmd = m_ptzQueue.front();
            m_ptzQueue.pop();
        }

        // Process the command asynchronously
        LONG lUserID = getSession(cmd.ip, cmd.port, cmd.username, cmd.password);
        if (lUserID < 0) {
            qWarning() << "[Hikvision PTZ Worker] Failed to get session for IP:" << cmd.ip;
            continue;
        }

        NET_DVR_DEVICEINFO_V40 deviceInfo;
        int targetChannel = cmd.channelId;
        if (getDeviceInfo(cmd.ip, deviceInfo)) {
            int startDChan = deviceInfo.struDeviceV30.byStartDChan;
            int chanNum = deviceInfo.struDeviceV30.byChanNum;
            int startChan = deviceInfo.struDeviceV30.byStartChan;
            if (startDChan > 0 && cmd.channelId < startDChan) {
                if (cmd.channelId <= chanNum) {
                    targetChannel = startChan + cmd.channelId - 1;
                } else {
                    targetChannel = startDChan + (cmd.channelId - chanNum) - 1;
                }
                qDebug() << "[Hikvision PTZ Worker] Translated logical channel" << cmd.channelId << "to SDK channel ID" << targetChannel;
            }
        }

        DWORD dwStop = cmd.stop ? 1 : 0;
        BOOL ret = NET_DVR_PTZControl_Other(lUserID, static_cast<LONG>(targetChannel), static_cast<DWORD>(cmd.command), dwStop);
        if (!ret) {
            DWORD err = NET_DVR_GetLastError();
            qWarning() << "[Hikvision PTZ Worker] PTZ Control failed for IP:" << cmd.ip << "Channel:" << targetChannel 
                       << "Command:" << cmd.command << "Stop:" << cmd.stop << "Error:" << err;
        } else {
            qDebug() << "[Hikvision PTZ Worker] PTZ Control succeeded for IP:" << cmd.ip << "Channel:" << targetChannel 
                     << "Command:" << cmd.command << "Stop:" << cmd.stop;
        }
    }
}

LONG HikvisionManager::loginShared(const QString &ip, int port, const QString &username, const QString &password, NET_DVR_DEVICEINFO_V40 &deviceInfo)
{
    bool wasLogged = false;
    bool isLoggedNow = false;
    LONG lUserID = -1;

    {
        std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);
        if (m_sharedSessions.contains(ip)) {
            auto &session = m_sharedSessions[ip];
            session.refCount++;
            deviceInfo = session.deviceInfo;
            qDebug() << "[Hikvision Shared] Reusing session for IP:" << ip << "UserID:" << session.lUserID << "RefCount:" << session.refCount;
            return session.lUserID;
        }
        wasLogged = isLoggedInternal(ip);
    }

    qDebug() << "[Hikvision Shared] Creating NEW session for IP:" << ip << ":" << port;

    ensureInitialized();

    if (!m_initialized) {
        qWarning() << "[Hikvision Shared] Cannot login: SDK not initialized.";
        return -1;
    }

    NET_DVR_USER_LOGIN_INFO loginInfo;
    std::memset(&loginInfo, 0, sizeof(NET_DVR_USER_LOGIN_INFO));
    std::strncpy(loginInfo.sDeviceAddress, ip.toUtf8().constData(), sizeof(loginInfo.sDeviceAddress) - 1);
    loginInfo.wPort = static_cast<WORD>(port);
    std::strncpy(loginInfo.sUserName, username.toUtf8().constData(), sizeof(loginInfo.sUserName) - 1);
    std::strncpy(loginInfo.sPassword, password.toUtf8().constData(), sizeof(loginInfo.sPassword) - 1);
    loginInfo.bUseAsynLogin = FALSE;
    loginInfo.byLoginMode = 0;

    NET_DVR_DEVICEINFO_V40 devInfo;
    std::memset(&devInfo, 0, sizeof(NET_DVR_DEVICEINFO_V40));

    lUserID = NET_DVR_Login_V40(&loginInfo, &devInfo);
    if (lUserID < 0) {
        DWORD err = NET_DVR_GetLastError();
        qWarning() << "[Hikvision Shared] Login FAILED for IP:" << ip << "Error:" << err;
        return -1;
    }

    {
        std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);
        SharedSession session;
        session.lUserID = lUserID;
        session.deviceInfo = devInfo;
        session.refCount = 1;

        m_sharedSessions.insert(ip, session);
        deviceInfo = devInfo;
        isLoggedNow = isLoggedInternal(ip);
    }

    qDebug() << "[Hikvision Shared] Login SUCCESS for IP:" << ip << "UserID:" << lUserID;
    if (wasLogged != isLoggedNow) {
        emit sessionStatusChanged(ip, isLoggedNow);
    }
    return lUserID;
}

void HikvisionManager::logoutShared(const QString &ip)
{
    bool wasLogged = false;
    bool isLoggedNow = false;
    LONG lUserIDToLogout = -1;

    {
        std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);
        wasLogged = isLoggedInternal(ip);
        if (m_sharedSessions.contains(ip)) {
            auto &session = m_sharedSessions[ip];
            session.refCount--;
            qDebug() << "[Hikvision Shared] Decremented refCount for IP:" << ip << "New RefCount:" << session.refCount;
            if (session.refCount <= 0) {
                lUserIDToLogout = session.lUserID;
                m_sharedSessions.remove(ip);
            }
        }
        isLoggedNow = isLoggedInternal(ip);
    }

    if (lUserIDToLogout >= 0) {
        ensureInitialized();
        NET_DVR_Logout(lUserIDToLogout);
        qDebug() << "[Hikvision Shared] Logged out session for IP:" << ip << "UserID:" << lUserIDToLogout;
    }

    if (wasLogged != isLoggedNow) {
        emit sessionStatusChanged(ip, isLoggedNow);
    }
}

void HikvisionManager::ensureInitialized() const
{
    std::unique_lock<std::mutex> lock(m_initMutex);
    m_initCond.wait(lock, [this]() { return m_initCompleted; });
}
