#include "hikvisionplayer.h"
#include <QPainter>
#include <QPen>
#include <QBrush>
#include <QDebug>
#include <cmath>

HikvisionPlayer::HikvisionPlayer(QQuickItem *parent)
    : QQuickPaintedItem(parent)
    , m_recorderPort(8000)
    , m_channelId(1)
    , m_streamType(1) // Default to SUB stream
    , m_playHandle(-1)
    , m_userId(-1)
    , m_frameCounter(0)
    , m_simulatedBitrate(250) // Default to 250 kbps for SUB
{
    // Start simulation timer at 25 FPS (40ms ticks)
    m_timer = new QTimer(this);
    connect(m_timer, &QTimer::timeout, this, &HikvisionPlayer::onFrameTimerTick);
    m_timer->start(40);
}

HikvisionPlayer::~HikvisionPlayer()
{
    if (m_playHandle >= 0) {
        NET_DVR_StopRealPlay(m_playHandle);
    }
}

void HikvisionPlayer::onFrameTimerTick()
{
    m_frameCounter++;
    
    // Simulate real-time bitrate fluctuations
    if (m_streamType == 0) { // MAIN
        // Fluctuate around 2.2 - 2.8 Mbps
        m_simulatedBitrate = 2200 + (std::sin(m_frameCounter * 0.1) * 300) + (std::rand() % 50);
    } else { // SUB
        // Fluctuate around 180 - 240 kbps
        m_simulatedBitrate = 180 + (std::sin(m_frameCounter * 0.15) * 30) + (std::rand() % 10);
    }
    
    // Force repaint
    update();
}

void HikvisionPlayer::restartStream()
{
    if (m_playHandle >= 0) {
        NET_DVR_StopRealPlay(m_playHandle);
        m_playHandle = -1;
    }

    if (m_recorderIp.isEmpty()) {
        return;
    }

    // Attempt proprietary connection
    qDebug() << "[Hikvision] Starting real-time stream for IP:" << m_recorderIp 
             << "Channel:" << m_channelId 
             << "Type:" << (m_streamType == 0 ? "MAIN" : "SUB");

    NET_DVR_PREVIEWINFO previewInfo;
    std::memset(&previewInfo, 0, sizeof(NET_DVR_PREVIEWINFO));
    previewInfo.lChannel = m_channelId;
    previewInfo.dwStreamType = static_cast<DWORD>(m_streamType);
    previewInfo.dwLinkMode = 0; // TCP
    previewInfo.hPlayWnd = 0;
    previewInfo.bBlocked = FALSE;

    m_playHandle = NET_DVR_RealPlay_V40(m_userId, &previewInfo, nullptr, nullptr);
}

void HikvisionPlayer::paint(QPainter *painter)
{
    painter->setRenderHint(QPainter::Antialiasing, true);

    const int w = width();
    const int h = height();

    // 1. Draw sleek high-tech background grid
    painter->fillRect(0, 0, w, h, QColor("#0c0f12")); // Deep dark navy space
    
    painter->setPen(QPen(QColor("#151d24"), 1, Qt::DotLine));
    const int gridSpacing = 40;
    for (int x = 0; x < w; x += gridSpacing) {
        painter->drawLine(x, 0, x, h);
    }
    for (int y = 0; y < h; y += gridSpacing) {
        painter->drawLine(0, y, w, y);
    }

    // 2. Draw subtle tech corner brackets
    painter->setPen(QPen(QColor("#ff7a00"), 2)); // Custom matching orange color
    const int br = 15;
    // Top-Left
    painter->drawLine(10, 10, 10 + br, 10);
    painter->drawLine(10, 10, 10, 10 + br);
    // Top-Right
    painter->drawLine(w - 10, 10, w - 10 - br, 10);
    painter->drawLine(w - 10, 10, w - 10, 10 + br);
    // Bottom-Left
    painter->drawLine(10, h - 10, 10 + br, h - 10);
    painter->drawLine(10, h - 10, 10, h - 10 - br);
    // Bottom-Right
    painter->drawLine(w - 10, h - 10, w - 10 - br, h - 10);
    painter->drawLine(w - 10, h - 10, w - 10, h - 10 - br);

    // 3. Draw blinking live REC indicator
    bool showRec = (m_frameCounter / 15) % 2 == 0;
    if (showRec) {
        painter->setBrush(QBrush(QColor("#ff2222")));
        painter->setPen(Qt::NoPen);
        painter->drawEllipse(20, 20, 10, 10);
        
        painter->setPen(QPen(QColor("#ffffff"), 1));
        QFont font = painter->font();
        font.setPixelSize(10);
        font.setBold(true);
        painter->setFont(font);
        painter->drawText(35, 29, "REC");
    }

    // 4. Draw OSD real-time clock (top right)
    QDateTime current = QDateTime::currentDateTime();
    QString timeStr = current.toString("yyyy-MM-dd hh:mm:ss.zzz");
    painter->setPen(QPen(QColor("#eeeeee"), 1));
    QFont clockFont = painter->font();
    clockFont.setPixelSize(11);
    clockFont.setFamily("Courier New"); // Monospaced for dates
    painter->setFont(clockFont);
    painter->drawText(w - 200, 29, timeStr);

    // 5. Draw center title
    QFont titleFont = painter->font();
    titleFont.setPixelSize(qMax(12, h / 18));
    titleFont.setBold(true);
    painter->setFont(titleFont);
    painter->setPen(QPen(QColor("#3a86ff"), 1)); // Clean modern blue
    QString cameraTitle = QString("IP CAMERA %1").arg(m_channelId);
    QRect textRect = painter->fontMetrics().boundingRect(cameraTitle);
    painter->drawText((w - textRect.width()) / 2, (h + textRect.height()) / 2, cameraTitle);

    // 6. Draw connection and stream details (bottom left)
    QFont detailsFont = painter->font();
    detailsFont.setPixelSize(10);
    painter->setFont(detailsFont);
    painter->setPen(QPen(QColor("#8898a6"), 1));
    painter->drawText(20, h - 35, QString("PROTOCOL: HIKVISION PRIVATE ON PORT %1").arg(m_recorderPort));
    painter->drawText(20, h - 20, QString("ADDRESS: %1").arg(m_recorderIp));

    // 7. Draw resolution and bitrate specs (bottom right)
    painter->setPen(QPen(QColor("#ff7a00"), 1));
    QString streamName = (m_streamType == 0) ? "MAIN (1080p)" : "SUB (360p)";
    QString bitrateStr = (m_simulatedBitrate >= 1000) 
                         ? QString("%1 Mbps").arg(QString::number(m_simulatedBitrate / 1000.0, 'f', 2))
                         : QString("%1 kbps").arg(m_simulatedBitrate);
    painter->drawText(w - 180, h - 35, QString("STREAM: %1").arg(streamName));
    painter->drawText(w - 180, h - 20, QString("BITRATE: %1").arg(bitrateStr));

    // 8. Draw animated tech visualizer waveform in the bottom center
    painter->setPen(QPen(QColor("#00f5d4"), 1)); // Neon turquoise wave
    const int waveWidth = 100;
    const int waveX = (w - waveWidth) / 2;
    const int waveY = h - 25;
    for (int idx = 0; idx < waveWidth; idx++) {
        double angle = (idx * 0.2) + (m_frameCounter * 0.1);
        int dy = std::sin(angle) * (m_streamType == 0 ? 8 : 3); // larger wave for MAIN stream!
        painter->drawPoint(waveX + idx, waveY + dy);
    }
}

void HikvisionPlayer::setRecorderIp(const QString &ip)
{
    if (m_recorderIp != ip) {
        m_recorderIp = ip;
        emit recorderIpChanged();
        restartStream();
    }
}

void HikvisionPlayer::setRecorderPort(int port)
{
    if (m_recorderPort != port) {
        m_recorderPort = port;
        emit recorderPortChanged();
        restartStream();
    }
}

void HikvisionPlayer::setUsername(const QString &user)
{
    if (m_username != user) {
        m_username = user;
        emit usernameChanged();
        restartStream();
    }
}

void HikvisionPlayer::setPassword(const QString &pass)
{
    if (m_password != pass) {
        m_password = pass;
        emit passwordChanged();
        restartStream();
    }
}

void HikvisionPlayer::setChannelId(int ch)
{
    if (m_channelId != ch) {
        m_channelId = ch;
        emit channelIdChanged();
        restartStream();
    }
}

void HikvisionPlayer::setStreamType(int type)
{
    if (m_streamType != type) {
        m_streamType = type;
        emit streamTypeChanged();
        restartStream();
    }
}
