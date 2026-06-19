#include "hikvisionisapi.h"
#include <QNetworkRequest>
#include <QUrl>
#include <QXmlStreamReader>
#include <QDebug>
#include <QThread>

HikvisionISAPI::HikvisionISAPI(QObject *parent)
    : QObject(parent)
{
    m_netManager = new QNetworkAccessManager(this);
    connect(m_netManager, &QNetworkAccessManager::authenticationRequired,
            this, &HikvisionISAPI::onAuthenticationRequired);
}

void HikvisionISAPI::searchRecordings(const QVariantMap &recorderInfo, int channelId, const QDateTime &start, const QDateTime &end)
{
    QString sessionId = QUuid::createUuid().toString();
    HikvisionSearchSession session;
    session.recorderInfo = recorderInfo;
    session.channelId = channelId;
    session.startTime = start;
    session.endTime = end;
    session.isMonthSearch = false;
    session.currentPosition = 1;
    m_sessions[sessionId] = session;

    doSearchRequest(sessionId);
}

void HikvisionISAPI::searchMonthAvailability(const QVariantMap &recorderInfo, int channelId, int year, int month)
{
    QString sessionId = QUuid::createUuid().toString();
    HikvisionSearchSession session;
    session.recorderInfo = recorderInfo;
    session.channelId = channelId;
    
    QDate firstDay(year, month, 1);
    QDate lastDay(year, month, firstDay.daysInMonth());
    
    session.startTime = QDateTime(firstDay, QTime(0, 0, 0), Qt::LocalTime);
    session.endTime = QDateTime(lastDay, QTime(23, 59, 59), Qt::LocalTime);
    session.isMonthSearch = true;
    session.year = year;
    session.month = month;
    session.currentPosition = 1;
    m_sessions[sessionId] = session;

    doSearchRequest(sessionId);
}

void HikvisionISAPI::doSearchRequest(const QString &sessionId)
{
    if (!m_sessions.contains(sessionId)) return;
    const HikvisionSearchSession &session = m_sessions[sessionId];

    QString ip = session.recorderInfo["ip"].toString();
    QString portStr = session.recorderInfo["port"].toString();
    m_currentUser = session.recorderInfo["username"].toString();
    m_currentPassword = session.recorderInfo["password"].toString();

    int port = portStr.toInt();
    if (port == 8000) port = 80;

    QUrl url(QString("http://%1:%2/ISAPI/ContentMgmt/search").arg(ip).arg(port));
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/xml");

    QString startTimeStr = session.startTime.toUTC().toString("yyyy-MM-ddThh:mm:ss") + "Z";
    QString endTimeStr = session.endTime.toUTC().toString("yyyy-MM-ddThh:mm:ss") + "Z";

    qDebug() << "[ISAPI] doSearchRequest session:" << sessionId
             << "channelId:" << session.channelId
             << "startTime (orig):" << session.startTime.toString(Qt::ISODate)
             << "startTime (local):" << session.startTime.toLocalTime().toString(Qt::ISODate)
             << "startTimeStr:" << startTimeStr
             << "endTimeStr:" << endTimeStr
             << "pos:" << session.currentPosition;

    QString xmlPayload = QString(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
        "<CMSearchDescription>\n"
        "  <searchID>%1</searchID>\n"
        "  <trackList>\n"
        "    <trackID>%2</trackID>\n"
        "  </trackList>\n"
        "  <timeSpanList>\n"
        "    <timeSpan>\n"
        "      <startTime>%3</startTime>\n"
        "      <endTime>%4</endTime>\n"
        "    </timeSpan>\n"
        "  </timeSpanList>\n"
        "  <maxResults>1000</maxResults>\n"
        "  <searchResultPostion>%5</searchResultPostion>\n"
        "  <metadataList>\n"
        "    <metadataDescriptor>//recordType.meta.std-cgi.com</metadataDescriptor>\n"
        "  </metadataList>\n"
        "</CMSearchDescription>\n"
    ).arg(sessionId).arg(session.channelId * 100 + 1).arg(startTimeStr).arg(endTimeStr).arg(session.currentPosition);

    QNetworkReply *reply = m_netManager->post(request, xmlPayload.toUtf8());
    reply->setProperty("sessionId", sessionId);
    reply->setProperty("username", m_currentUser);
    reply->setProperty("password", m_currentPassword);
    connect(reply, &QNetworkReply::finished, this, &HikvisionISAPI::onReplyFinished);
}

void HikvisionISAPI::onAuthenticationRequired(QNetworkReply *reply, QAuthenticator *authenticator)
{
    if (reply) {
        QString user = reply->property("username").toString();
        QString pass = reply->property("password").toString();
        if (!user.isEmpty()) {
            authenticator->setUser(user);
            authenticator->setPassword(pass);
            return;
        }
    }
    authenticator->setUser(m_currentUser);
    authenticator->setPassword(m_currentPassword);
}

void HikvisionISAPI::onReplyFinished()
{
    QNetworkReply *reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;

    QString sessionId = reply->property("sessionId").toString();
    reply->deleteLater();

    if (!m_sessions.contains(sessionId)) {
        return; // Session cancelled or already finished
    }
    
    HikvisionSearchSession &session = m_sessions[sessionId];
    QString recorderIp = session.recorderInfo["ip"].toString();

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[ISAPI] Search failed:" << reply->errorString();
        if (session.isMonthSearch) {
            QVariantList daysList;
            for (int d : session.accumulatedDays) daysList.append(d);
            emit monthAvailabilityFinished(recorderIp, session.channelId, session.year, session.month, daysList);
        } else {
            if (session.accumulatedSegments.count() > 0) {
                emit searchFinished(recorderIp, session.channelId, session.startTime, session.accumulatedSegments);
            } else {
                emit searchFailed(recorderIp, session.channelId, session.startTime, reply->errorString());
            }
        }
        m_sessions.remove(sessionId);
        return;
    }

    QByteArray response = reply->readAll();
    QXmlStreamReader xml(response);

    bool inMatchList = false;
    bool inMatchItem = false;
    QString responseStatusStrg;
    
    QDateTime currentStart;
    QDateTime currentEnd;
    
    int matchItemsCount = 0;

    while (!xml.atEnd() && !xml.hasError()) {
        QXmlStreamReader::TokenType token = xml.readNext();

        if (token == QXmlStreamReader::StartElement) {
            QString name = xml.name().toString();
            if (name == "responseStatusStrg") {
                responseStatusStrg = xml.readElementText().trimmed();
            } else if (name == "matchList") {
                inMatchList = true;
            } else if (inMatchList && name == "searchMatchItem") {
                inMatchItem = true;
                matchItemsCount++;
            } else if (inMatchItem && name == "startTime") {
                QString val = xml.readElementText();
                currentStart = QDateTime::fromString(val, Qt::ISODate).toLocalTime();
            } else if (inMatchItem && name == "endTime") {
                QString val = xml.readElementText();
                currentEnd = QDateTime::fromString(val, Qt::ISODate).toLocalTime();
            }
        } else if (token == QXmlStreamReader::EndElement) {
            QString name = xml.name().toString();
            if (name == "matchList") {
                inMatchList = false;
            } else if (name == "searchMatchItem") {
                inMatchItem = false;
                if (currentStart.isValid() && currentEnd.isValid()) {
                    if (session.isMonthSearch) {
                        int day = currentStart.date().day();
                        if (!session.accumulatedDays.contains(day)) {
                            session.accumulatedDays.append(day);
                        }
                    } else {
                        QVariantMap segment;
                        segment["startTime"] = currentStart.toMSecsSinceEpoch();
                        segment["endTime"] = currentEnd.toMSecsSinceEpoch();
                        session.accumulatedSegments.append(segment);
                    }
                }
                currentStart = QDateTime();
                currentEnd = QDateTime();
            }
        }
    }

    if (xml.hasError() || matchItemsCount == 0) {
        // Done paginating
        if (session.isMonthSearch) {
            QVariantList daysList;
            for (int d : session.accumulatedDays) {
                daysList.append(d);
            }
            qDebug() << "[ISAPI] Month availability finished (no more matches) for channel:" << session.channelId << "days:" << daysList;
            emit monthAvailabilityFinished(recorderIp, session.channelId, session.year, session.month, daysList);
        } else {
            qDebug() << "[ISAPI] Day search finished (no more matches) for channel:" << session.channelId << "segments:" << session.accumulatedSegments.count();
            emit searchFinished(recorderIp, session.channelId, session.startTime, session.accumulatedSegments);
        }
        m_sessions.remove(sessionId);
        return;
    }

    // If responseStatusStrg is MORE, there are more pages (limit to 100000 results to avoid infinite loop)
    if (responseStatusStrg == "MORE" && session.currentPosition < 100000) {
        qDebug() << "[ISAPI] Session" << sessionId << "status MORE; paginating next page from:" << (session.currentPosition + matchItemsCount);
        session.currentPosition += matchItemsCount;
        doSearchRequest(sessionId); // Fetch next page
    } else {
        // Done paginating
        if (session.isMonthSearch) {
            QVariantList daysList;
            for (int d : session.accumulatedDays) {
                daysList.append(d);
            }
            qDebug() << "[ISAPI] Month availability finished for channel:" << session.channelId << "days:" << daysList;
            emit monthAvailabilityFinished(recorderIp, session.channelId, session.year, session.month, daysList);
        } else {
            qDebug() << "[ISAPI] Day search finished for channel:" << session.channelId << "segments:" << session.accumulatedSegments.count();
            emit searchFinished(recorderIp, session.channelId, session.startTime, session.accumulatedSegments);
        }
        m_sessions.remove(sessionId);
    }
}
