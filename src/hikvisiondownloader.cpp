#include "hikvisiondownloader.h"
#include "qmlav/src/qmlavdemuxer.h"
#include <QDebug>
#include <QThread>
#include <QDir>
#include <QFileInfo>

HikvisionDownloader::HikvisionDownloader(QObject *parent)
    : QObject(parent)
    , m_isDownloading(false)
    , m_isConverting(false)
    , m_progress(0)
    , m_statusText("")
    , m_lUserID(-1)
    , m_lFileHandle(-1)
{
    m_timer = new QTimer(this);
    m_timer->setInterval(1000);
    connect(m_timer, &QTimer::timeout, this, &HikvisionDownloader::checkProgress);

    m_ffmpegProcess = new QProcess(this);
    connect(m_ffmpegProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), this, &HikvisionDownloader::onFfmpegFinished);
}

HikvisionDownloader::~HikvisionDownloader()
{
    stopDownload();
}

bool HikvisionDownloader::isDownloading() const
{
    return m_isDownloading;
}

bool HikvisionDownloader::isConverting() const
{
    return m_isConverting;
}

QString HikvisionDownloader::statusText() const
{
    return m_statusText;
}

int HikvisionDownloader::progress() const
{
    return m_progress;
}

int HikvisionDownloader::overallProgress() const
{
    if (m_totalSegmentsCount <= 0) return 0;
    return ((m_currentSegmentIndex * 100) + m_progress) / m_totalSegmentsCount;
}

void HikvisionDownloader::startDownload(const QVariantMap &recorderInfo, int channelId, const QDateTime &start, const QDateTime &end, const QString &saveFilePath)
{
    if (m_isDownloading) {
        emit downloadFinished(false, tr("Pobieranie już trwa."));
        return;
    }

    m_recorderInfo = recorderInfo;
    m_channelId = channelId;

    QString ip = recorderInfo["ip"].toString();
    int port = recorderInfo["port"].toInt();
    QString username = recorderInfo["username"].toString();
    QString password = recorderInfo["password"].toString();

    NET_DVR_USER_LOGIN_INFO loginInfo;
    std::memset(&loginInfo, 0, sizeof(NET_DVR_USER_LOGIN_INFO));
    std::strncpy(loginInfo.sDeviceAddress, ip.toUtf8().constData(), sizeof(loginInfo.sDeviceAddress) - 1);
    loginInfo.wPort = static_cast<WORD>(port);
    std::strncpy(loginInfo.sUserName, username.toUtf8().constData(), sizeof(loginInfo.sUserName) - 1);
    std::strncpy(loginInfo.sPassword, password.toUtf8().constData(), sizeof(loginInfo.sPassword) - 1);

    NET_DVR_DEVICEINFO_V40 deviceInfo;
    std::memset(&deviceInfo, 0, sizeof(NET_DVR_DEVICEINFO_V40));

    m_lUserID = NET_DVR_Login_V40(&loginInfo, &deviceInfo);
    if (m_lUserID < 0) {
        emit downloadFinished(false, tr("Błąd logowania do urządzenia: %1").arg(NET_DVR_GetLastError()));
        return;
    }

    int realSdkChannel = channelId;
    if (deviceInfo.struDeviceV30.byChanNum == 0 && deviceInfo.struDeviceV30.byIPChanNum > 0) {
        realSdkChannel = channelId + deviceInfo.struDeviceV30.byStartDChan - 1;
    } else if (deviceInfo.struDeviceV30.byChanNum > 0 && channelId > deviceInfo.struDeviceV30.byChanNum) {
        realSdkChannel = deviceInfo.struDeviceV30.byStartDChan + (channelId - deviceInfo.struDeviceV30.byChanNum) - 1;
    } else if (deviceInfo.struDeviceV30.byChanNum > 0 && channelId <= deviceInfo.struDeviceV30.byChanNum) {
        realSdkChannel = channelId + deviceInfo.struDeviceV30.byStartChan - 1;
    }
    m_realSdkChannel = realSdkChannel;

    // Find all physical recording files in this time range
    NET_DVR_FILECOND_V40 findCond;
    std::memset(&findCond, 0, sizeof(NET_DVR_FILECOND_V40));
    findCond.lChannel = static_cast<LONG>(realSdkChannel);
    findCond.dwFileType = 0xFF; // All types
    findCond.dwIsLocked = 0xFF; // All locks
    findCond.dwUseCardNo = 0;
    
    findCond.struStartTime.dwYear = start.date().year();
    findCond.struStartTime.dwMonth = start.date().month();
    findCond.struStartTime.dwDay = start.date().day();
    findCond.struStartTime.dwHour = start.time().hour();
    findCond.struStartTime.dwMinute = start.time().minute();
    findCond.struStartTime.dwSecond = start.time().second();

    findCond.struStopTime.dwYear = end.date().year();
    findCond.struStopTime.dwMonth = end.date().month();
    findCond.struStopTime.dwDay = end.date().day();
    findCond.struStopTime.dwHour = end.time().hour();
    findCond.struStopTime.dwMinute = end.time().minute();
    findCond.struStopTime.dwSecond = end.time().second();

    m_segments.clear();
    LONG lFindHandle = NET_DVR_FindFile_V40(m_lUserID, &findCond);
    if (lFindHandle >= 0) {
        NET_DVR_FINDDATA_V50 findData;
        while (true) {
            int state = NET_DVR_FindNextFile_V50(lFindHandle, &findData);
            if (state == 1000) { // NET_DVR_FILE_SUCCESS
                QDateTime fileStart(QDate(findData.struStartTime.wYear, findData.struStartTime.byMonth, findData.struStartTime.byDay),
                                    QTime(findData.struStartTime.byHour, findData.struStartTime.byMinute, findData.struStartTime.bySecond));
                QDateTime fileEnd(QDate(findData.struStopTime.wYear, findData.struStopTime.byMonth, findData.struStopTime.byDay),
                                  QTime(findData.struStopTime.byHour, findData.struStopTime.byMinute, findData.struStopTime.bySecond));
                
                QDateTime intersectStart = fileStart > start ? fileStart : start;
                QDateTime intersectEnd = fileEnd < end ? fileEnd : end;
                
                if (intersectStart < intersectEnd) {
                    DownloadSegment seg;
                    seg.startTime = intersectStart;
                    seg.endTime = intersectEnd;
                    m_segments.append(seg);
                }
            } else if (state == 1002) { // NET_DVR_ISFINDING
                QThread::msleep(10);
            } else {
                break;
            }
        }
        NET_DVR_FindClose_V30(lFindHandle);
    }

    if (m_segments.isEmpty()) {
        emit downloadFinished(false, tr("Brak nagrań w wybranym przedziale czasowym dla tej kamery."));
        NET_DVR_Logout(m_lUserID);
        m_lUserID = -1;
        return;
    }

    // Sort segments chronologically
    std::sort(m_segments.begin(), m_segments.end(), [](const DownloadSegment &a, const DownloadSegment &b) {
        return a.startTime < b.startTime;
    });

    // Generate filenames for segments
    QString baseFinal = saveFilePath;
    QString baseTemp = saveFilePath;
    if (baseTemp.endsWith(".mp4", Qt::CaseInsensitive)) {
        baseTemp.replace(baseTemp.length() - 4, 4, ".pspart");
    }

    int totalParts = m_segments.size();
    int padWidth = 1;
    if (totalParts > 99) {
        padWidth = 3;
    } else if (totalParts > 9) {
        padWidth = 2;
    }

    for (int i = 0; i < totalParts; ++i) {
        QString segFinal = baseFinal;
        QString segTemp = baseTemp;
        if (totalParts > 1) {
            int partNum = i + 1;
            QString suffix = QString("_%1").arg(partNum, padWidth, 10, QChar('0'));
            if (segFinal.endsWith(".mp4", Qt::CaseInsensitive)) {
                segFinal.insert(segFinal.length() - 4, suffix);
            } else {
                segFinal += suffix;
            }
            if (segTemp.endsWith(".pspart", Qt::CaseInsensitive)) {
                segTemp.insert(segTemp.length() - 7, suffix);
            } else {
                segTemp += suffix;
            }
        }
        m_segments[i].finalPath = segFinal;
        m_segments[i].tempPath = segTemp;
    }

    m_isDownloading = true;
    m_currentSegmentIndex = 0;
    m_totalSegmentsCount = m_segments.size();
    m_convertedSegmentsCount = 0;
    emit isDownloadingChanged();

    startNextSegment();
}

void HikvisionDownloader::startNextSegment()
{
    if (m_currentSegmentIndex >= m_segments.size()) {
        m_isDownloading = false;
        emit isDownloadingChanged();
        
        NET_DVR_Logout(m_lUserID);
        m_lUserID = -1;
        
        QString summaryMsg = tr("Pobrano i przekonwertowano %1 z %2 plików.").arg(m_convertedSegmentsCount).arg(m_totalSegmentsCount);
        m_statusText = summaryMsg;
        emit statusTextChanged();
        emit downloadFinished(true, summaryMsg);
        return;
    }

    const DownloadSegment &seg = m_segments.at(m_currentSegmentIndex);
    m_tempFilePath = seg.tempPath;
    m_finalFilePath = seg.finalPath;

    NET_DVR_PLAYCOND downloadCond;
    std::memset(&downloadCond, 0, sizeof(NET_DVR_PLAYCOND));
    downloadCond.dwChannel = static_cast<DWORD>(m_realSdkChannel);
    downloadCond.struStartTime.dwYear = seg.startTime.date().year();
    downloadCond.struStartTime.dwMonth = seg.startTime.date().month();
    downloadCond.struStartTime.dwDay = seg.startTime.date().day();
    downloadCond.struStartTime.dwHour = seg.startTime.time().hour();
    downloadCond.struStartTime.dwMinute = seg.startTime.time().minute();
    downloadCond.struStartTime.dwSecond = seg.startTime.time().second();

    downloadCond.struStopTime.dwYear = seg.endTime.date().year();
    downloadCond.struStopTime.dwMonth = seg.endTime.date().month();
    downloadCond.struStopTime.dwDay = seg.endTime.date().day();
    downloadCond.struStopTime.dwHour = seg.endTime.time().hour();
    downloadCond.struStopTime.dwMinute = seg.endTime.time().minute();
    downloadCond.struStopTime.dwSecond = seg.endTime.time().second();

    downloadCond.byStreamType = 0; // Main stream
    downloadCond.byCourseFile = 0;
    downloadCond.byDownload = 0;

    QFileInfo fileInfo(m_tempFilePath);
    QDir().mkpath(fileInfo.absolutePath());
    QByteArray pathBytes = m_tempFilePath.toLocal8Bit();

    m_lFileHandle = NET_DVR_GetFileByTime_V40(m_lUserID, pathBytes.data(), &downloadCond);
    if (m_lFileHandle < 0) {
        NET_DVR_TIME startTimeOld;
        std::memset(&startTimeOld, 0, sizeof(NET_DVR_TIME));
        startTimeOld.dwYear = seg.startTime.date().year();
        startTimeOld.dwMonth = seg.startTime.date().month();
        startTimeOld.dwDay = seg.startTime.date().day();
        startTimeOld.dwHour = seg.startTime.time().hour();
        startTimeOld.dwMinute = seg.startTime.time().minute();
        startTimeOld.dwSecond = seg.startTime.time().second();
        
        NET_DVR_TIME stopTimeOld;
        std::memset(&stopTimeOld, 0, sizeof(NET_DVR_TIME));
        stopTimeOld.dwYear = seg.endTime.date().year();
        stopTimeOld.dwMonth = seg.endTime.date().month();
        stopTimeOld.dwDay = seg.endTime.date().day();
        stopTimeOld.dwHour = seg.endTime.time().hour();
        stopTimeOld.dwMinute = seg.endTime.time().minute();
        stopTimeOld.dwSecond = seg.endTime.time().second();
        
        m_lFileHandle = NET_DVR_GetFileByTime(m_lUserID, m_realSdkChannel, &startTimeOld, &stopTimeOld, pathBytes.data());
    }

    if (m_lFileHandle < 0) {
        int err = NET_DVR_GetLastError();
        NET_DVR_Logout(m_lUserID);
        m_lUserID = -1;
        m_isDownloading = false;
        emit isDownloadingChanged();
        emit downloadFinished(false, tr("Błąd inicjalizacji pobierania części %1: %2").arg(m_currentSegmentIndex + 1).arg(err));
        return;
    }

    if (!NET_DVR_PlayBackControl_V40(m_lFileHandle, NET_DVR_PLAYSTART, nullptr, 0, nullptr, nullptr)) {
        NET_DVR_StopGetFile(m_lFileHandle);
        NET_DVR_Logout(m_lUserID);
        m_lFileHandle = -1;
        m_lUserID = -1;
        m_isDownloading = false;
        emit isDownloadingChanged();
        emit downloadFinished(false, tr("Błąd startu pobierania części %1: %2").arg(m_currentSegmentIndex + 1).arg(NET_DVR_GetLastError()));
        return;
    }

    m_progress = 0;
    m_lastFileSize = 0;
    emit progressChanged();
    emit overallProgressChanged();

    m_statusText = tr("Pobieranie części %1 z %2...").arg(m_currentSegmentIndex + 1).arg(m_totalSegmentsCount);
    emit statusTextChanged();

    m_timer->start();
}

void HikvisionDownloader::stopDownload()
{
    if (!m_isDownloading) return;

    m_timer->stop();
    m_segments.clear();

    if (m_ffmpegProcess->state() != QProcess::NotRunning) {
        m_ffmpegProcess->kill();
        m_ffmpegProcess->waitForFinished(1000);
        QFile::remove(m_tempFilePath);
        QFile::remove(m_finalFilePath);
    }

    if (m_lFileHandle >= 0) {
        NET_DVR_StopGetFile(m_lFileHandle);
        m_lFileHandle = -1;
    }

    if (m_lUserID >= 0) {
        NET_DVR_Logout(m_lUserID);
        m_lUserID = -1;
    }

    m_isDownloading = false;
    m_isConverting = false;
    emit isConvertingChanged();
    m_progress = 0;
    m_statusText = tr("Zatrzymano");
    emit isDownloadingChanged();
    emit progressChanged();
    emit overallProgressChanged();
    emit statusTextChanged();
    emit downloadFinished(false, tr("Pobieranie przerwane przez użytkownika."));
}

void HikvisionDownloader::checkProgress()
{
    if (m_lFileHandle < 0) return;

    QFileInfo fi(m_tempFilePath);
    if (fi.exists()) {
        qint64 currentSize = fi.size();
        qint64 diff = currentSize - m_lastFileSize;
        if (diff > 0) {
            g_networkBytesAccumulator.fetch_add(diff, std::memory_order_relaxed);
        }
        m_lastFileSize = currentSize;
    }

    int pos = NET_DVR_GetDownloadPos(m_lFileHandle);
    
    if (pos == 100 || pos == 200 || pos < 0) {
        m_timer->stop();
        NET_DVR_StopGetFile(m_lFileHandle);
        m_lFileHandle = -1;
        
        QFileInfo finalFi(m_tempFilePath);
        if (finalFi.exists()) {
            qint64 currentSize = finalFi.size();
            qint64 diff = currentSize - m_lastFileSize;
            if (diff > 0) {
                g_networkBytesAccumulator.fetch_add(diff, std::memory_order_relaxed);
            }
            m_lastFileSize = currentSize;
        }

        bool isSuccess = (pos == 100) || (finalFi.exists() && finalFi.size() > 102400); // 100 KB
        
        if (isSuccess) {
            m_progress = 100;
            emit progressChanged();
            emit overallProgressChanged();
            
            if (m_finalFilePath.endsWith(".mp4", Qt::CaseInsensitive)) {
                m_isConverting = true;
                emit isConvertingChanged();
                m_statusText = tr("Konwertowanie części %1 z %2...").arg(m_currentSegmentIndex + 1).arg(m_totalSegmentsCount);
                emit statusTextChanged();
                m_ffmpegProcess->start("ffmpeg", QStringList() << "-y" << "-i" << m_tempFilePath << "-c:v" << "copy" << "-c:a" << "aac" << m_finalFilePath);
            } else {
                m_convertedSegmentsCount++;
                m_currentSegmentIndex++;
                startNextSegment();
            }
        } else {
            if (m_lUserID >= 0) {
                NET_DVR_Logout(m_lUserID);
                m_lUserID = -1;
            }
            m_isDownloading = false;
            m_isConverting = false;
            emit isConvertingChanged();
            m_progress = 0;
            emit isDownloadingChanged();
            emit progressChanged();
            emit overallProgressChanged();
            emit downloadFinished(false, tr("Błąd w trakcie pobierania części %1.").arg(m_currentSegmentIndex + 1));
        }
    } else {
        if (m_progress != pos) {
            m_progress = pos;
            emit progressChanged();
            emit overallProgressChanged();
        }
    }
}

void HikvisionDownloader::onFfmpegFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    m_isConverting = false;
    emit isConvertingChanged();

    if (exitStatus == QProcess::NormalExit && exitCode == 0) {
        QFile::remove(m_tempFilePath);
        m_convertedSegmentsCount++;
        m_currentSegmentIndex++;
        m_statusText = tr("Pobrano i przekonwertowano %1 z %2 części...").arg(m_convertedSegmentsCount).arg(m_totalSegmentsCount);
        emit statusTextChanged();
        
        startNextSegment();
    } else {
        m_isDownloading = false;
        emit isDownloadingChanged();
        if (m_lUserID >= 0) {
            NET_DVR_Logout(m_lUserID);
            m_lUserID = -1;
        }
        QByteArray stderrOutput = m_ffmpegProcess->readAllStandardError();
        QByteArray stdoutOutput = m_ffmpegProcess->readAllStandardOutput();
        
        QString shortError = QString::fromUtf8(stderrOutput.trimmed());
        if (shortError.isEmpty()) {
            shortError = tr("Błąd wewnętrzny FFmpeg");
        } else {
            QStringList lines = shortError.split('\n');
            if (!lines.isEmpty()) {
                shortError = lines.last().trimmed();
                if (shortError.isEmpty() && lines.size() > 1) {
                    shortError = lines[lines.size() - 2].trimmed();
                }
            }
        }
        emit downloadFinished(false, tr("Konwersja części %1 na MP4 nie powiodła się: %2").arg(m_currentSegmentIndex + 1).arg(shortError.left(100)));
    }
}
