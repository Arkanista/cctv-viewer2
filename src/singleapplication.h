#ifndef SINGLEAPPLICATION_H
#define SINGLEAPPLICATION_H

#include <QObject>
#include <QLocalServer>
#include <QLocalSocket>
#include <QDir>
#include <QFileInfo>
#include <QCoreApplication>
#include <QSettings>

class SingleApplication : public QObject
{
    Q_OBJECT

public:
    explicit SingleApplication(QObject *parent = nullptr)
        : QObject(parent),
          m_socketName(QFileInfo(QCoreApplication::applicationFilePath()).fileName() + "-cctv-viewer-socket")
    {
        // Read configuration to check if single application mode is enabled
        QSettings settings(QSettings().fileName(), QSettings::NativeFormat);
        bool singleAppEnabled = settings.value("singleApplication", true).toBool();

        if (!singleAppEnabled || QCoreApplication::arguments().contains("--auxiliary")) {
            m_running = false;
            return;
        }

        // Try to connect to existing server to see if it's running
        QLocalSocket socket;
        socket.connectToServer(m_socketName);
        if (socket.waitForConnected(100)) {
            // Connected! Another instance is running.
            m_running = true;
            // Send the request to open a new window
            socket.write("openNewWindow");
            socket.waitForBytesWritten(1000);
            socket.disconnectFromServer();
        } else {
            // Not running. We are the first instance!
            m_running = false;
            // Clean up any left-over socket file from crash
            QLocalServer::removeServer(m_socketName);
            m_server = new QLocalServer(this);
            connect(m_server, &QLocalServer::newConnection, this, &SingleApplication::handleNewConnection);
            m_server->listen(m_socketName);
        }
    }

    ~SingleApplication() {
        if (m_server) {
            m_server->close();
            QLocalServer::removeServer(m_socketName);
        }
    }

    Q_INVOKABLE bool isRunning() { return m_running; }

signals:
    void messageReceived(const QString &message);

private slots:
    void handleNewConnection() {
        if (!m_server) return;
        QLocalSocket *socket = m_server->nextPendingConnection();
        if (socket) {
            connect(socket, &QLocalSocket::readyRead, this, [this, socket]() {
                QByteArray data = socket->readAll();
                QString msg = QString::fromUtf8(data);
                emit messageReceived(msg);
            });
            connect(socket, &QLocalSocket::disconnected, socket, &QLocalSocket::deleteLater);
        }
    }

private:
    QString m_socketName;
    QLocalServer *m_server = nullptr;
    bool m_running = false;
};

#endif // SINGLEAPPLICATION_H
