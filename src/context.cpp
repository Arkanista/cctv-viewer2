#include <algorithm>
#include <QRandomGenerator>
#include <QFile>
#include <QDir>
#include <QSettings>
#include <QFileInfo>
#include <QCoreApplication>
#include <QLocale>
#include <QFileDialog>
#include <QApplication>
#include <QWidget>
#include "context.h"

Context::Context(QObject *parent) : QObject(parent)
{
    m_instances.append(this);
}

Context::~Context()
{
    m_instances.removeOne(this);
    if (m_instances.isEmpty()) {
        for (QProcess *process : m_childProcesses) {
            if (process->state() != QProcess::NotRunning) {
                process->terminate();
                process->waitForFinished(1000);
            }
        }
        delete m_config;
        m_config = nullptr;
    }
}

void Context::init()
{
    QCommandLineOption configOption({{"c", "config"}, tr("Path to the config file."), "config"});
    QCommandLineOption presetOption({{"p", "preset"}, tr("Index of the current preset."), "preset"});
    QCommandLineOption fullScreenOption({{"f", "full-screen"}, tr("Force full-screen mode.")});
    QCommandLineOption kioskModeOption({{"k", "kiosk"}, tr("Kiosk mode functionality.")});
    QCommandLineOption logOption({{"l", "log"}, tr("Log level [%1...%2].").arg(Config::LogBeginRange).arg(Config::LogEndRange), "level"});
    QCommandLineOption auxiliaryOption(QStringList("auxiliary"), tr("Start as an auxiliary window."));
    QCommandLineOption auxiliaryIdOption("auxiliary-id", tr("ID of the auxiliary window."), "id");
    QCommandLineOption verboseOption("verbose", tr("Pokaż szczegółowe logi w konsoli (verbose logging)."));

    parseCommandLineOptions({configOption,
                            presetOption,
                            fullScreenOption,
                            kioskModeOption,
                            logOption,
                            auxiliaryOption,
                            auxiliaryIdOption,
                            verboseOption});

    m_isAuxiliary = m_commandLineParser.isSet(auxiliaryOption);
    m_enableLogs = m_commandLineParser.isSet(verboseOption);

    if (m_isAuxiliary && m_commandLineParser.isSet(auxiliaryIdOption)) {
        m_auxiliaryId = m_commandLineParser.value(auxiliaryIdOption).toInt();
    } else {
        m_auxiliaryId = 0;
    }

    if (m_commandLineParser.isSet(configOption)) {
        m_config = new Config(m_commandLineParser.value(configOption));
    } else {
        m_config = new Config();
    }

    // Ensure the config file exists so we can watch it
    QString configPath = m_config->fileName();
    QFile file(configPath);
    if (!file.exists()) {
        QFileInfo fileInfo(configPath);
        QDir().mkpath(fileInfo.absolutePath());
        if (file.open(QIODevice::WriteOnly)) {
            file.close();
        }
    }

    // Configure the File Watcher
    if (!m_watcher) {
        m_watcher = new QFileSystemWatcher();
        m_watcher->addPath(configPath);
        QObject::connect(m_watcher, &QFileSystemWatcher::fileChanged, [](const QString &path) {
            // Force reload settings file cache
            QSettings settings;
            settings.sync();

            // Re-add to watcher in case the file was recreated/replaced
            if (m_watcher && !m_watcher->files().contains(path)) {
                m_watcher->addPath(path);
            }

            // Emit signal on all active Context instances
            for (Context *instance : m_instances) {
                emit instance->configFileChanged();
            }
        });
    }

    if (m_commandLineParser.isSet(presetOption)) {
        m_config->setCurrentIndex(m_commandLineParser.value(presetOption).toInt());
    }
    m_config->setFullScreen(m_commandLineParser.isSet(fullScreenOption));
    m_config->setKioskMode(m_commandLineParser.isSet(kioskModeOption));
    if (m_commandLineParser.isSet(logOption)) {
        auto level = std::clamp(m_commandLineParser.value(logOption).toInt(),
                                static_cast<int>(Config::LogBeginRange),
                                static_cast<int>(Config::LogEndRange));
        m_config->setLogLevel(static_cast<Config::LogLevel>(level));
    }
}

void Context::parseCommandLineOptions(const QList<QCommandLineOption> &options)
{
    m_commandLineParser.setApplicationDescription(tr("CCTV Viewer - viewer and mounter video streams."));
    m_commandLineParser.addHelpOption();
    m_commandLineParser.addVersionOption();

    m_commandLineParser.addOptions(options);

    QCoreApplication *app = QCoreApplication::instance();
    if (app) {
        m_commandLineParser.process(*app);
    }
}

void Context::startAuxiliaryProcess()
{
    QString exePath = QCoreApplication::applicationFilePath();
    QString mainConfigPath = m_config ? m_config->fileName() : QSettings().fileName();

    int nextId = 1;
    while (m_childIds.values().contains(nextId)) {
        nextId++;
    }

    QProcess *process = new QProcess();
    QStringList arguments;
    arguments << "-c" << mainConfigPath << "--auxiliary" << "--auxiliary-id" << QString::number(nextId);

    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), 
            [process](int exitCode, QProcess::ExitStatus exitStatus) {
        Q_UNUSED(exitCode);
        Q_UNUSED(exitStatus);
        m_childIds.remove(process);
        m_childProcesses.removeOne(process);
        process->deleteLater();
    });

    m_childIds[process] = nextId;
    m_childProcesses.append(process);
    process->start(exePath, arguments);
}

QVariant Context::readSetting(const QString &category, const QString &key, const QVariant &defaultValue) const
{
    QString path = m_config ? m_config->fileName() : QSettings().fileName();
    QSettings settings(path, QSettings::IniFormat);
    if (!category.isEmpty()) {
        settings.beginGroup(category);
    }
    QVariant val = settings.value(key, defaultValue);
    if (!category.isEmpty()) {
        settings.endGroup();
    }
    
    // Coerce the returned QVariant to the same type as defaultValue
    // to prevent QML from receiving strings (e.g. "false") which are truthy in JavaScript.
    if (defaultValue.type() == QVariant::Bool) {
        return val.toBool();
    } else if (defaultValue.type() == QVariant::Int) {
        return val.toInt();
    } else if (defaultValue.type() == QVariant::Double) {
        return val.toDouble();
    }
    return val;
}

void Context::initLanguage()
{
    QSettings settings(m_config ? m_config->fileName() : QSettings().fileName(), QSettings::IniFormat);
    QString lang = settings.value("language", "system").toString();
    m_language = lang;
    
    if (m_translator) {
        QCoreApplication::removeTranslator(m_translator);
    }
    
    QString transFile;
    if (lang == "pl") {
        transFile = "cctv-viewer_pl_PL";
    } else if (lang == "en") {
        transFile = "cctv-viewer_en_US";
    } else if (lang == "system") {
        QString locale = QLocale::system().name();
        if (locale.startsWith("pl", Qt::CaseInsensitive)) {
            transFile = "cctv-viewer_pl_PL";
        } else {
            transFile = "cctv-viewer_en_US";
        }
    }
    
    if (!transFile.isEmpty()) {
        if (!m_translator) {
            m_translator = new QTranslator(QCoreApplication::instance());
        }
        if (m_translator->load(transFile, ":/translations/")) {
            QCoreApplication::installTranslator(m_translator);
        }
    }
}

void Context::setLanguage(const QString &lang)
{
    m_language = lang;
    
    if (m_translator) {
        QCoreApplication::removeTranslator(m_translator);
    }
    
    QString transFile;
    if (lang == "pl") {
        transFile = "cctv-viewer_pl_PL";
    } else if (lang == "en") {
        transFile = "cctv-viewer_en_US";
    } else if (lang == "system") {
        QString locale = QLocale::system().name();
        if (locale.startsWith("pl", Qt::CaseInsensitive)) {
            transFile = "cctv-viewer_pl_PL";
        } else {
            transFile = "cctv-viewer_en_US";
        }
    }
    
    if (!transFile.isEmpty()) {
        if (!m_translator) {
            m_translator = new QTranslator(QCoreApplication::instance());
        }
        if (m_translator->load(transFile, ":/translations/")) {
            QCoreApplication::installTranslator(m_translator);
        }
    }
    
    QSettings settings(m_config ? m_config->fileName() : QSettings().fileName(), QSettings::IniFormat);
    settings.setValue("language", lang);
    
    if (m_engine) {
        m_engine->retranslate();
    }
    emit languageChanged();
}

QString Context::getLanguage() const
{
    return m_language.isEmpty() ? "system" : m_language;
}

bool Context::mkpath(const QString &dirPath) const
{
    return QDir().mkpath(dirPath);
}

bool Context::dirExists(const QString &dirPath) const
{
    if (dirPath.isEmpty())
        return false;
    QFileInfo info(dirPath);
    return info.exists() && info.isDir() && info.isReadable();
}

QString Context::homePath() const
{
    return QDir::homePath();
}

QUrl Context::pathToUrl(const QString &path) const
{
    QFileInfo info(path);
    if (info.exists() && info.isDir()) {
        QString p = path;
        if (!p.endsWith('/') && !p.endsWith('\\')) {
            p += '/';
        }
        return QUrl::fromLocalFile(p);
    }
    return QUrl::fromLocalFile(path);
}

QString Context::selectFolder(const QString &title, const QString &initialPath) const
{
    QWidget *parent = QApplication::activeWindow();
    QString dir = QFileDialog::getExistingDirectory(
        parent,
        title,
        initialPath,
        QFileDialog::ShowDirsOnly | QFileDialog::DontResolveSymlinks
    );
    return dir;
}

QString Context::readLocalFile(const QString &filePath) const
{
    QString path = filePath;
    if (path.startsWith("qrc:/")) {
        path = path.mid(3); // convert "qrc:/..." to ":/..."
    }
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return QString();
    }
    return QString::fromUtf8(file.readAll());
}

#ifdef __linux__
#include <malloc.h>
#endif

void Context::trimMemory()
{
    if (m_engine) {
        qDebug() << "[Context] Aggressively trimming QML component cache, singletons, and collecting JS garbage...";
        m_engine->collectGarbage();
        m_engine->trimComponentCache();
    }
#ifdef __linux__
    qDebug() << "[Context] Manual memory trim triggered. Releasing free heap arenas to OS...";
    malloc_trim(0);
#endif
}


