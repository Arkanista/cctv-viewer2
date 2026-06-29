#ifndef HIKVISIONMANAGER_H
#define HIKVISIONMANAGER_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QHash>
#include <QList>
#include <QThread>
#include <mutex>
#include <queue>
#include <condition_variable>
#include <thread>
#include "hcnetsdk_compat.h"

class HikvisionManager : public QObject
{
    Q_OBJECT

public:
    explicit HikvisionManager(QObject *parent = nullptr);
    ~HikvisionManager() override;

    // Singleton provider
    static HikvisionManager* instance();

    // Login and discover channels for a specific recorder
    Q_INVOKABLE QVariantList discoverCameras(const QString &ip, int port, const QString &username, const QString &password);
    Q_INVOKABLE void discoverCamerasAsync(const QString &ip, int port, const QString &username, const QString &password);

    // Logout from a recorder session
    Q_INVOKABLE void logout(const QString &ip);

    // Check if logged in to a recorder
    Q_INVOKABLE bool isLogged(const QString &ip);

    // PTZ zoom control
    Q_INVOKABLE bool ptzZoom(const QString &ip, int port, const QString &username, const QString &password, int channelId, int command, bool stop);

    // Shared session management for playback players
    struct SharedSession {
        LONG lUserID = -1;
        NET_DVR_DEVICEINFO_V40 deviceInfo;
        int refCount = 0;
    };

    LONG loginShared(const QString &ip, int port, const QString &username, const QString &password, NET_DVR_DEVICEINFO_V40 &deviceInfo);
    void logoutShared(const QString &ip);
    void forceLogoutShared(const QString &ip);

    LONG getSession(const QString &ip, int port, const QString &username, const QString &password);
    bool getDeviceInfo(const QString &ip, NET_DVR_DEVICEINFO_V40 &deviceInfo);

signals:
    void sessionStatusChanged(const QString &ip, bool loggedIn);
    void discoveryFinished(const QString &ip, const QVariantList &cameras, bool success, const QString &errorMsg);

private:
    struct SessionInfo {
        LONG lUserID = -1;
        NET_DVR_DEVICEINFO_V40 deviceInfo;
    };

    bool isLoggedInternal(const QString &ip) const;

    static HikvisionManager* m_instance;
    QHash<QString, SessionInfo> m_sessions; // Maps IP to SessionInfo
    QHash<QString, SharedSession> m_sharedSessions;
    std::mutex m_sharedSessionsMutex;
    bool m_initialized;

    struct PtzCommand {
        QString ip;
        int port;
        QString username;
        QString password;
        int channelId;
        int command;
        bool stop;
    };

    std::queue<PtzCommand> m_ptzQueue;
    std::mutex m_ptzMutex;
    std::condition_variable m_ptzCond;
    std::thread m_ptzWorker;
    bool m_ptzWorkerStop = false;

    void ptzWorkerLoop();
    void ensureInitialized() const;

    mutable std::mutex m_initMutex;
    mutable std::condition_variable m_initCond;
    bool m_initCompleted = false;

    QList<QThread*> m_discoveryThreads;
    std::mutex m_discoveryMutex;
};

#endif // HIKVISIONMANAGER_H
