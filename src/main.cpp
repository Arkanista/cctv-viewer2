#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTranslator>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSettings>
#include <unistd.h>
#include <sys/types.h>
#include <cstdarg>

extern "C" {
#include <libavutil/log.h>
}

#include "qmlavplayer.h"
#include "thumbnailprovider.h"
#include "context.h"
#include "eventfilter.h"
#include "clipboard.h"
#include "singleapplication.h"
#include "viewportslayoutscollectionmodel.h"
#include "hikvisionmanager.h"
#include "nvrstatusmanager.h"
#include "hikvisionplayer.h"
#include "hikvisionarchiveplayer.h"
#include "hikvisionisapi.h"
#include "hikvisiondownloader.h"
#include "systemstats.h"

void custom_ffmpeg_log_callback(void* ptr, int level, const char* fmt, va_list vl)
{
    Q_UNUSED(ptr);
    Q_UNUSED(level);
    Q_UNUSED(fmt);
    Q_UNUSED(vl);
}

void customMessageHandler(QtMsgType type, const QMessageLogContext &context, const QString &msg)
{
    Q_UNUSED(context);
    if (!Context::enableLogs()) {
        if (type == QtDebugMsg || type == QtInfoMsg || type == QtWarningMsg) {
            return;
        }
    }

    QByteArray localMsg = msg.toLocal8Bit();
    switch (type) {
    case QtDebugMsg:
        fprintf(stderr, "%s\n", localMsg.constData());
        break;
    case QtInfoMsg:
        fprintf(stderr, "%s\n", localMsg.constData());
        break;
    case QtWarningMsg:
        fprintf(stderr, "Warning: %s\n", localMsg.constData());
        break;
    case QtCriticalMsg:
        fprintf(stderr, "Critical: %s\n", localMsg.constData());
        break;
    case QtFatalMsg:
        fprintf(stderr, "Fatal: %s\n", localMsg.constData());
        abort();
    }
}

void registerQmlTypes()
{
    qmlRegisterSingletonType<Context>("CCTV_Viewer.Core", 1, 0, "Context",
                                      []([[maybe_unused]] QQmlEngine *engine,
                                         [[maybe_unused]] QJSEngine *scriptEngine) -> QObject * {
        return new Context();
    });
    qmlRegisterSingletonType<Clipboard>("CCTV_Viewer.Utils", 1, 0, "Clipboard",
                                                []([[maybe_unused]] QQmlEngine *engine,
                                                   [[maybe_unused]] QJSEngine *scriptEngine) -> QObject * {
                                                      return new Clipboard();
                                                  });

    qmlRegisterType<HikvisionPlayer>("CCTV_Viewer.Hikvision", 1, 0, "HikvisionPlayer");
    qmlRegisterType<HikvisionArchivePlayer>("CCTV_Viewer.Hikvision", 1, 0, "HikvisionArchivePlayer");
    qmlRegisterType<HikvisionDownloader>("CCTV_Viewer.Hikvision", 1, 0, "HikvisionDownloader");

    qmlRegisterSingletonType<HikvisionISAPI>("CCTV_Viewer.Hikvision", 1, 0, "HikvisionISAPI",
                                             []([[maybe_unused]] QQmlEngine *engine,
                                                [[maybe_unused]] QJSEngine *scriptEngine) -> QObject * {
        return new HikvisionISAPI();
    });

    qmlRegisterType<QmlAVPlayer>("CCTV_Viewer.Multimedia", 1, 0, "QmlAVPlayer");
    qmlRegisterType<ViewportsLayoutItem>("CCTV_Viewer.Models", 1, 0, "ViewportsLayoutItem");
    qmlRegisterType<ViewportsLayoutModel>("CCTV_Viewer.Models", 1, 0, "ViewportsLayoutModel");
    qmlRegisterType<ViewportsLayoutsCollectionModel>("CCTV_Viewer.Models", 1, 0, "ViewportsLayoutsCollectionModel");

    qmlRegisterType<EventFilter>("CCTV_Viewer.Utils", 1, 0, "EventFilter");

    qmlRegisterSingletonType<SystemStats>("CCTV_Viewer.Core", 1, 0, "SystemStats",
                                          []([[maybe_unused]] QQmlEngine *engine,
                                             [[maybe_unused]] QJSEngine *scriptEngine) -> QObject * {
        return new SystemStats();
    });
}

int countAuxiliaryProcesses()
{
    qint64 selfPid = getpid();
    uid_t myUid = getuid();
    QString selfExe = QFile::symLinkTarget(QString("/proc/%1/exe").arg(selfPid));

    int count = 0;
    QDir procDir("/proc");
    QStringList entries = procDir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    for (const QString &entry : entries) {
        bool ok = false;
        qint64 pid = entry.toLongLong(&ok);
        if (!ok || pid == selfPid) continue;

        // Check UID
        QFile statusFile(QString("/proc/%1/status").arg(pid));
        uid_t procUid = -1;
        if (statusFile.open(QIODevice::ReadOnly)) {
            QByteArray content = statusFile.readAll();
            statusFile.close();
            int uidIdx = content.indexOf("Uid:");
            if (uidIdx != -1) {
                int lineEnd = content.indexOf('\n', uidIdx);
                QByteArray line = content.mid(uidIdx, lineEnd - uidIdx);
                QList<QByteArray> parts = line.split('\t');
                for (const QByteArray &p : parts) {
                    bool numOk = false;
                    uint val = p.trimmed().toUInt(&numOk);
                    if (numOk) {
                        procUid = val;
                        break;
                    }
                }
                if (procUid == -1) {
                    QList<QByteArray> partsSpace = line.split(' ');
                    for (const QByteArray &p : partsSpace) {
                        bool numOk = false;
                        uint val = p.trimmed().toUInt(&numOk);
                        if (numOk) {
                            procUid = val;
                            break;
                        }
                    }
                }
            }
        }
        if (procUid != myUid) continue;

        // Check executable path
        QString exePath = QFile::symLinkTarget(QString("/proc/%1/exe").arg(pid));
        if (exePath.isEmpty() || exePath != selfExe) {
            continue;
        }

        // Check cmdline
        QFile cmdFile(QString("/proc/%1/cmdline").arg(pid));
        if (cmdFile.open(QIODevice::ReadOnly)) {
            QByteArray cmdline = cmdFile.readAll();
            cmdFile.close();
            QList<QByteArray> args = cmdline.split('\0');
            bool isAux = false;
            for (const QByteArray &arg : args) {
                if (arg == "--auxiliary") {
                    isAux = true;
                    break;
                }
            }
            if (isAux) {
                count++;
            }
        }
    }
    return count;
}

int main(int argc, char *argv[])
{
    qInstallMessageHandler(customMessageHandler);
    av_log_set_callback(custom_ffmpeg_log_callback);
#if QT_VERSION >= QT_VERSION_CHECK(5, 14, 0)
    QGuiApplication::setHighDpiScaleFactorRoundingPolicy(Qt::HighDpiScaleFactorRoundingPolicy::PassThrough);
#endif
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);
    QCoreApplication::setAttribute(Qt::AA_UseHighDpiPixmaps);

#if defined(APP_NAME)
    QCoreApplication::setApplicationName(QLatin1String(APP_NAME));
#endif
#if defined(APP_VERSION)
    QCoreApplication::setApplicationVersion(QLatin1String(APP_VERSION));
#endif
#if defined(ORG_NAME)
    QCoreApplication::setOrganizationName(QLatin1String(ORG_NAME));
#endif
#if defined(ORG_DOMAIN)
    QCoreApplication::setOrganizationDomain(QLatin1String(ORG_DOMAIN));
#endif
    QApplication::setDesktopFileName(QStringLiteral("kvision"));

    registerQmlTypes();

    QApplication app(argc, argv);
    app.setFont(QFont("DejaVu Sans Condensed"));
    app.setDesktopFileName(QStringLiteral("kvision"));

    SingleApplication singleApp;
    if (singleApp.isRunning()) {
        Context::init();
        qInfo() << "KVision version:" << APP_VERSION;
        Context::initLanguage();
        QQmlApplicationEngine engine;
        Context::setEngine(&engine);
        auto *hikvisionManager = new HikvisionManager();
        qmlRegisterSingletonInstance("CCTV_Viewer.Hikvision", 1, 0, "HikvisionManager", hikvisionManager);
        engine.addImportPath(":/src/imports");
        const QUrl url(QStringLiteral("qrc:/src/SingleInstanceWarning.qml"));
        QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app, [url](QObject *obj, const QUrl &objUrl) {
            if (!obj && url == objUrl)
                QCoreApplication::exit(-1);
        }, Qt::QueuedConnection);
        engine.load(url);
        return app.exec();
    }

    Context::init();
    qInfo() << "KVision version:" << APP_VERSION;
    Context::initLanguage();

    if (Context::isAuxiliary()) {
        QString configPath = Context::config() ? Context::config()->fileName() : QSettings().fileName();
        QSettings settings(configPath, QSettings::IniFormat);
        int limit = settings.value("auxiliaryLimit", 1).toInt();
        if (limit < 0) limit = 0;
        if (limit > 3) limit = 3;

        int activeAuxCount = countAuxiliaryProcesses();
        fprintf(stderr, "[Limit Check] Auxiliary process starting (PID: %lld). Active aux windows: %d, Limit: %d\n", 
                (long long)getpid(), activeAuxCount, limit);
        fflush(stderr);

        if (activeAuxCount >= limit) {
            fprintf(stderr, "[Limit Check] Limit reached! Loading warning popup...\n");
            fflush(stderr);
            QQmlApplicationEngine engine;
            Context::setEngine(&engine);
            engine.addImportPath(":/src/imports");
            const QUrl url(QStringLiteral("qrc:/src/AuxiliaryLimitWarning.qml"));
            QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app, [url](QObject *obj, const QUrl &objUrl) {
                if (!obj && url == objUrl) {
                    fprintf(stderr, "[Limit Check] Failed to load AuxiliaryLimitWarning.qml from resources!\n");
                    fflush(stderr);
                    QCoreApplication::exit(-1);
                }
            }, Qt::QueuedConnection);
            engine.load(url);
            return app.exec();
        }
    }

    QQmlApplicationEngine engine;
    Context::setEngine(&engine);
    engine.rootContext()->setContextProperty("SingleApplication", &singleApp);

    auto *hikvisionManager = new HikvisionManager();
    qmlRegisterSingletonInstance("CCTV_Viewer.Hikvision", 1, 0, "HikvisionManager", hikvisionManager);

    auto *nvrStatusManager = new NvrStatusManager();
    qmlRegisterSingletonInstance("CCTV_Viewer.Hikvision", 1, 0, "NvrStatusManager", nvrStatusManager);

    // Thumbnail provider for camera previews
    auto *thumbnailProvider = new ThumbnailProvider();
    qmlRegisterSingletonInstance("CCTV_Viewer.Utils", 1, 0, "ThumbnailProvider", thumbnailProvider);
    engine.addImageProvider(QStringLiteral("thumbnail"), new ThumbnailImageProvider(thumbnailProvider));
    QIcon appIcon;
    appIcon.addFile(QStringLiteral(":/images/128.png"), QSize(128, 128));
    appIcon.addFile(QStringLiteral(":/images/256.png"), QSize(256, 256));
    appIcon.addFile(QStringLiteral(":/images/512.png"), QSize(512, 512));
    app.setWindowIcon(appIcon);

    engine.addImportPath(":/src/imports");
    const QUrl url(QStringLiteral("qrc:/src/RootWindow.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated, &app, [url](QObject *obj, const QUrl &objUrl) {
        if (!obj && url == objUrl)
            QCoreApplication::exit(-1);
    }, Qt::QueuedConnection);
    engine.load(url);

    // NOTE: Debug
    // Testing Right-to-left User Interfaces...
    // (This code must be removed!!!)
//    QGuiApplication::setLayoutDirection(Qt::RightToLeft);

    return app.exec();
}
