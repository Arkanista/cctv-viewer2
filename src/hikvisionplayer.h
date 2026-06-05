#ifndef HIKVISIONPLAYER_H
#define HIKVISIONPLAYER_H

#include <QQuickPaintedItem>
#include <QTimer>
#include <QDateTime>
#include "hcnetsdk_compat.h"

class HikvisionPlayer : public QQuickPaintedItem
{
    Q_OBJECT

    Q_PROPERTY(QString recorderIp READ recorderIp WRITE setRecorderIp NOTIFY recorderIpChanged)
    Q_PROPERTY(int recorderPort READ recorderPort WRITE setRecorderPort NOTIFY recorderPortChanged)
    Q_PROPERTY(QString username READ username WRITE setUsername NOTIFY usernameChanged)
    Q_PROPERTY(QString password READ password WRITE setPassword NOTIFY passwordChanged)
    Q_PROPERTY(int channelId READ channelId WRITE setChannelId NOTIFY channelIdChanged)
    Q_PROPERTY(int streamType READ streamType WRITE setStreamType NOTIFY streamTypeChanged)

public:
    explicit HikvisionPlayer(QQuickItem *parent = nullptr);
    ~HikvisionPlayer() override;

    // Painting routine
    void paint(QPainter *painter) override;

    // Properties getters & setters
    QString recorderIp() const { return m_recorderIp; }
    void setRecorderIp(const QString &ip);

    int recorderPort() const { return m_recorderPort; }
    void setRecorderPort(int port);

    QString username() const { return m_username; }
    void setUsername(const QString &user);

    QString password() const { return m_password; }
    void setPassword(const QString &pass);

    int channelId() const { return m_channelId; }
    void setChannelId(int ch);

    int streamType() const { return m_streamType; }
    void setStreamType(int type);

signals:
    void recorderIpChanged();
    void recorderPortChanged();
    void usernameChanged();
    void passwordChanged();
    void channelIdChanged();
    void streamTypeChanged();

private slots:
    void onFrameTimerTick();

private:
    void restartStream();

    // Stream state
    QString m_recorderIp;
    int m_recorderPort;
    QString m_username;
    QString m_password;
    int m_channelId;
    int m_streamType; // 0-main, 1-sub

    // Hikvision session handles
    LONG m_playHandle;
    LONG m_userId;

    // Simulation variables
    QTimer *m_timer;
    qint64 m_frameCounter;
    int m_simulatedBitrate; // in kbps
};

#endif // HIKVISIONPLAYER_H
