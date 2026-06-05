#include "hikvisiondownloader.h"
#include "qmlav/src/qmlavdemuxer.h"
#include <QDebug>
#include <QThread>
#include <QDir>
#include <QFileInfo>

HikvisionDownloader::HikvisionDownloader(QObject *parent)
    : QObject(parent)
    , m_isDownloading(false)
    , m_progress(0)
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

int HikvisionDownloader::progress() const
{
    return m_progress;
}

void HikvisionDownloader::startDownload(const QVariantMap &recorderInfo, int channelId, const QDateTime &start, const QDateTime &end, const QString &saveFilePath)
{
    if (m_isDownloading) {
        emit downloadFinished(false, "Pobieranie już trwa.");
        return;
    }

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
        emit downloadFinished(false, QString("Błąd logowania do urządzenia: %1").arg(NET_DVR_GetLastError()));
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

    NET_DVR_PLAYCOND downloadCond;
    std::memset(&downloadCond, 0, sizeof(NET_DVR_PLAYCOND));
    downloadCond.dwChannel = static_cast<DWORD>(realSdkChannel);

    downloadCond.struStartTime.dwYear = start.date().year();
    downloadCond.struStartTime.dwMonth = start.date().month();
    downloadCond.struStartTime.dwDay = start.date().day();
    downloadCond.struStartTime.dwHour = start.time().hour();
    downloadCond.struStartTime.dwMinute = start.time().minute();
    downloadCond.struStartTime.dwSecond = start.time().second();

    downloadCond.struStopTime.dwYear = end.date().year();
    downloadCond.struStopTime.dwMonth = end.date().month();
    downloadCond.struStopTime.dwDay = end.date().day();
    downloadCond.struStopTime.dwHour = end.time().hour();
    downloadCond.struStopTime.dwMinute = end.time().minute();
    downloadCond.struStopTime.dwSecond = end.time().second();

    // Check if any files exist in this time range first
    NET_DVR_FILECOND_V40 findCond;
    std::memset(&findCond, 0, sizeof(NET_DVR_FILECOND_V40));
    findCond.lChannel = static_cast<LONG>(realSdkChannel);
    findCond.dwFileType = 0xFF; // All types
    findCond.dwIsLocked = 0xFF; // All locks
    findCond.dwUseCardNo = 0;
    findCond.struStartTime = downloadCond.struStartTime;
    findCond.struStopTime = downloadCond.struStopTime;

    LONG lFindHandle = NET_DVR_FindFile_V40(m_lUserID, &findCond);
    if (lFindHandle >= 0) {
        NET_DVR_FINDDATA_V50 findData;
        int state = NET_DVR_FindNextFile_V50(lFindHandle, &findData);
        NET_DVR_FindClose_V30(lFindHandle);
        if (state == NET_DVR_FILE_NOFIND || state == NET_DVR_NOMOREFILE) {
            emit downloadFinished(false, "Brak nagrań w wybranym przedziale czasowym dla tej kamery.");
            NET_DVR_Logout(m_lUserID);
            m_lUserID = -1;
            return;
        }
    }

    downloadCond.byStreamType = 0; // Main stream
    downloadCond.byCourseFile = 0;
    downloadCond.byDownload = 0; // 0 is default network download, 1 might trigger NVR local USB backup

    m_finalFilePath = saveFilePath;
    m_tempFilePath = saveFilePath;
    if (m_finalFilePath.endsWith(".mp4", Qt::CaseInsensitive)) {
        m_tempFilePath.replace(m_tempFilePath.length() - 4, 4, ".ps");
    }

    QFileInfo fileInfo(m_tempFilePath);
    QDir().mkpath(fileInfo.absolutePath());

    QByteArray pathBytes = m_tempFilePath.toLocal8Bit();
    
    qDebug() << "[HikArchive] Downloading logical channel" << channelId << "(SDK channel" << realSdkChannel << ") from" << start << "to" << end << "into" << m_tempFilePath;
    
    m_lFileHandle = NET_DVR_GetFileByTime_V40(m_lUserID, pathBytes.data(), &downloadCond);

    if (m_lFileHandle < 0) {
        qDebug() << "[HikArchive] NET_DVR_GetFileByTime_V40 failed:" << NET_DVR_GetLastError();
        // Fallback to older API
        NET_DVR_TIME startTimeOld;
        std::memset(&startTimeOld, 0, sizeof(NET_DVR_TIME));
        startTimeOld.dwYear = start.date().year();
        startTimeOld.dwMonth = start.date().month();
        startTimeOld.dwDay = start.date().day();
        startTimeOld.dwHour = start.time().hour();
        startTimeOld.dwMinute = start.time().minute();
        startTimeOld.dwSecond = start.time().second();
        
        NET_DVR_TIME stopTimeOld;
        std::memset(&stopTimeOld, 0, sizeof(NET_DVR_TIME));
        stopTimeOld.dwYear = end.date().year();
        stopTimeOld.dwMonth = end.date().month();
        stopTimeOld.dwDay = end.date().day();
        stopTimeOld.dwHour = end.time().hour();
        stopTimeOld.dwMinute = end.time().minute();
        stopTimeOld.dwSecond = end.time().second();
        
        m_lFileHandle = NET_DVR_GetFileByTime(m_lUserID, realSdkChannel, &startTimeOld, &stopTimeOld, pathBytes.data());
    }

    if (m_lFileHandle < 0) {
        int err = NET_DVR_GetLastError();
        qDebug() << "[HikArchive] NET_DVR_GetFileByTime failed:" << err;
        NET_DVR_Logout(m_lUserID);
        m_lUserID = -1;
        emit downloadFinished(false, QString("Błąd inicjalizacji pobierania: %1").arg(err));
        return;
    }

    if (!NET_DVR_PlayBackControl_V40(m_lFileHandle, NET_DVR_PLAYSTART, nullptr, 0, nullptr, nullptr)) {
        NET_DVR_StopGetFile(m_lFileHandle);
        NET_DVR_Logout(m_lUserID);
        m_lFileHandle = -1;
        m_lUserID = -1;
        emit downloadFinished(false, QString("Błąd startu pobierania: %1").arg(NET_DVR_GetLastError()));
        return;
    }

    m_isDownloading = true;
    m_progress = 0;
    m_lastFileSize = 0;
    emit isDownloadingChanged();
    emit progressChanged();

    m_timer->start();
}

void HikvisionDownloader::stopDownload()
{
    if (!m_isDownloading) return;

    m_timer->stop();

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
    m_progress = 0;
    emit isDownloadingChanged();
    emit progressChanged();
    emit downloadFinished(false, "Pobieranie przerwane przez użytkownika.");
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
        NET_DVR_Logout(m_lUserID);
        m_lFileHandle = -1;
        m_lUserID = -1;
        
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
            
            if (m_finalFilePath.endsWith(".mp4", Qt::CaseInsensitive)) {
                emit downloadFinished(true, pos == 100 ? "Konwertowanie na MP4..." : "Zakończono (z ostrzeżeniem). Konwertowanie na MP4...");
                m_ffmpegProcess->start("ffmpeg", QStringList() << "-y" << "-i" << m_tempFilePath << "-c:v" << "copy" << "-c:a" << "aac" << m_finalFilePath);
            } else {
                m_isDownloading = false;
                emit isDownloadingChanged();
                emit downloadFinished(true, pos == 100 ? "Pobieranie zakończone pomyślnie." : "Pobieranie zakończone (z ostrzeżeniem).");
            }
        } else {
            m_isDownloading = false;
            m_progress = 0;
            emit isDownloadingChanged();
            emit progressChanged();
            emit downloadFinished(false, "Błąd w trakcie pobierania (np. błąd sieci lub brak pliku).");
        }
    } else {
        if (m_progress != pos) {
            m_progress = pos;
            emit progressChanged();
        }
    }
}

void HikvisionDownloader::onFfmpegFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    m_isDownloading = false;
    emit isDownloadingChanged();

    if (exitStatus == QProcess::NormalExit && exitCode == 0) {
        QFile::remove(m_tempFilePath);
        emit downloadFinished(true, "Pobieranie i konwersja na MP4 zakończone pomyślnie.");
    } else {
        QByteArray stderrOutput = m_ffmpegProcess->readAllStandardError();
        QByteArray stdoutOutput = m_ffmpegProcess->readAllStandardOutput();
        qDebug() << "[HikArchive] FFmpeg conversion failed with exitCode" << exitCode << "and status" << exitStatus;
        qDebug() << "[HikArchive] FFmpeg stderr:" << stderrOutput;
        qDebug() << "[HikArchive] FFmpeg stdout:" << stdoutOutput;
        
        QString shortError = QString::fromUtf8(stderrOutput.trimmed());
        if (shortError.isEmpty()) {
            shortError = "Błąd wewnętrzny FFmpeg";
        } else {
            // Take the last line or first line that has the actual error
            QStringList lines = shortError.split('\n');
            if (!lines.isEmpty()) {
                shortError = lines.last().trimmed();
                if (shortError.isEmpty() && lines.size() > 1) {
                    shortError = lines[lines.size() - 2].trimmed();
                }
            }
        }
        emit downloadFinished(false, QString("Pobieranie zakończone, ale konwersja na MP4 nie powiodła się: %1").arg(shortError.left(100)));
    }
}
