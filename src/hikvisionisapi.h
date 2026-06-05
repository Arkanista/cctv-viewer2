#ifndef HIKVISIONISAPI_H
#define HIKVISIONISAPI_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QAuthenticator>
#include <QVariantMap>
#include <QDateTime>
#include <QMap>
#include <QUuid>

struct PlaybackSegment {
    QDateTime startTime;
    QDateTime endTime;
};

struct HikvisionSearchSession {
    QVariantMap recorderInfo;
    int channelId;
    QDateTime startTime;
    QDateTime endTime;
    bool isMonthSearch;
    int year;
    int month;
    int currentPosition;
    QVariantList accumulatedSegments;
    QList<int> accumulatedDays;
};

class HikvisionISAPI : public QObject
{
    Q_OBJECT
public:
    explicit HikvisionISAPI(QObject *parent = nullptr);

    // Queries the NVR for available recordings
    // start, end: the date range to query
    Q_INVOKABLE void searchRecordings(const QVariantMap &recorderInfo, int channelId, const QDateTime &start, const QDateTime &end);
    Q_INVOKABLE void searchMonthAvailability(const QVariantMap &recorderInfo, int channelId, int year, int month);

signals:
    void searchFinished(const QString &recorderIp, int channelId, const QDateTime &startTime, const QVariantList &segments);
    void searchFailed(const QString &recorderIp, int channelId, const QDateTime &startTime, const QString &error);
    void monthAvailabilityFinished(const QString &recorderIp, int channelId, int year, int month, const QVariantList &daysWithRecords);

private slots:
    void onAuthenticationRequired(QNetworkReply *reply, QAuthenticator *authenticator);
    void onReplyFinished();

private:
    void doSearchRequest(const QString &sessionId);

    QNetworkAccessManager *m_netManager;
    QString m_currentUser;
    QString m_currentPassword;
    QMap<QString, HikvisionSearchSession> m_sessions;
};

#endif // HIKVISIONISAPI_H
