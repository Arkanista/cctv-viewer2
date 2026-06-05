#ifndef HIKVISIONMANAGER_H
#define HIKVISIONMANAGER_H

#include <QObject>
#include <QVariantList>
#include <QVariantMap>
#include <QHash>
#include <mutex>
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

    // Logout from a recorder session
    Q_INVOKABLE void logout(const QString &ip);

    // Shared session management for playback players
    struct SharedSession {
        LONG lUserID = -1;
        NET_DVR_DEVICEINFO_V40 deviceInfo;
        int refCount = 0;
    };

    LONG loginShared(const QString &ip, int port, const QString &username, const QString &password, NET_DVR_DEVICEINFO_V40 &deviceInfo);
    void logoutShared(const QString &ip);

private:
    static HikvisionManager* m_instance;
    QHash<QString, LONG> m_sessions; // Maps IP to UserID (lUserID)
    QHash<QString, SharedSession> m_sharedSessions;
    std::mutex m_sharedSessionsMutex;
    bool m_initialized;
};

#endif // HIKVISIONMANAGER_H
