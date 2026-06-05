#include "hikvisionmanager.h"
#include <QDebug>
#include <QProcess>
#include <QRegularExpression>
#include <QRegularExpressionMatchIterator>

HikvisionManager* HikvisionManager::m_instance = nullptr;

HikvisionManager::HikvisionManager(QObject *parent)
    : QObject(parent)
    , m_initialized(false)
{
    m_instance = this;
    if (NET_DVR_Init()) {
        m_initialized = true;
        qDebug() << "[Hikvision] HCNetSDK Initialized successfully.";
    } else {
        qWarning() << "[Hikvision] Failed to initialize HCNetSDK.";
    }
}

HikvisionManager::~HikvisionManager()
{
    // Logout all active sessions
    for (auto it = m_sessions.begin(); it != m_sessions.end(); ++it) {
        NET_DVR_Logout(it.value());
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

    m_sessions.insert(ip, lUserID);
    qDebug() << "[Hikvision] Logged in successfully to IP:" << ip << "with UserID:" << lUserID;

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

void HikvisionManager::logout(const QString &ip)
{
    if (m_sessions.contains(ip)) {
        LONG lUserID = m_sessions.take(ip);
        NET_DVR_Logout(lUserID);
        qDebug() << "[Hikvision] Logged out from IP:" << ip << "UserID:" << lUserID;
    }
}

LONG HikvisionManager::loginShared(const QString &ip, int port, const QString &username, const QString &password, NET_DVR_DEVICEINFO_V40 &deviceInfo)
{
    std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);

    if (m_sharedSessions.contains(ip)) {
        auto &session = m_sharedSessions[ip];
        session.refCount++;
        deviceInfo = session.deviceInfo;
        qDebug() << "[Hikvision Shared] Reusing session for IP:" << ip << "UserID:" << session.lUserID << "RefCount:" << session.refCount;
        return session.lUserID;
    }

    qDebug() << "[Hikvision Shared] Creating NEW session for IP:" << ip << ":" << port;

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

    LONG lUserID = NET_DVR_Login_V40(&loginInfo, &devInfo);
    if (lUserID < 0) {
        DWORD err = NET_DVR_GetLastError();
        qWarning() << "[Hikvision Shared] Login FAILED for IP:" << ip << "Error:" << err;
        return -1;
    }

    SharedSession session;
    session.lUserID = lUserID;
    session.deviceInfo = devInfo;
    session.refCount = 1;

    m_sharedSessions.insert(ip, session);
    deviceInfo = devInfo;

    qDebug() << "[Hikvision Shared] Login SUCCESS for IP:" << ip << "UserID:" << lUserID << "RefCount:" << session.refCount;
    return lUserID;
}

void HikvisionManager::logoutShared(const QString &ip)
{
    std::lock_guard<std::mutex> lock(m_sharedSessionsMutex);

    if (m_sharedSessions.contains(ip)) {
        auto &session = m_sharedSessions[ip];
        session.refCount--;
        qDebug() << "[Hikvision Shared] Decremented refCount for IP:" << ip << "New RefCount:" << session.refCount;
        if (session.refCount <= 0) {
            NET_DVR_Logout(session.lUserID);
            qDebug() << "[Hikvision Shared] Logged out session for IP:" << ip << "UserID:" << session.lUserID;
            m_sharedSessions.remove(ip);
        }
    }
}
