#include <QApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QTranslator>
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

    qmlRegisterSingletonType<HikvisionManager>("CCTV_Viewer.Hikvision", 1, 0, "HikvisionManager",
                                               []([[maybe_unused]] QQmlEngine *engine,
                                                  [[maybe_unused]] QJSEngine *scriptEngine) -> QObject * {
        return new HikvisionManager();
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

int main(int argc, char *argv[])
{
    av_log_set_callback(custom_ffmpeg_log_callback);
    QCoreApplication::setAttribute(Qt::AA_EnableHighDpiScaling);

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

    qInfo() << "CCTV Viewer version:" << APP_VERSION;

    registerQmlTypes();

    QApplication app(argc, argv);
    app.setFont(QFont("DejaVu Sans Condensed"));

    SingleApplication singleApp;
    if (singleApp.isRunning()) {
        Context::init();
        Context::initLanguage();
        QQmlApplicationEngine engine;
        Context::setEngine(&engine);
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
    Context::initLanguage();

    QQmlApplicationEngine engine;
    Context::setEngine(&engine);
    engine.rootContext()->setContextProperty("SingleApplication", &singleApp);

    // Thumbnail provider for camera previews
    auto *thumbnailProvider = new ThumbnailProvider();
    qmlRegisterSingletonInstance("CCTV_Viewer.Utils", 1, 0, "ThumbnailProvider", thumbnailProvider);
    engine.addImageProvider(QStringLiteral("thumbnail"), new ThumbnailImageProvider(thumbnailProvider));
    app.setWindowIcon(QIcon(QLatin1String(":/images/cctv-viewer2-icon.png")));

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
