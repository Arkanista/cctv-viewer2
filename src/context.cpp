#include <algorithm>
#include <QRandomGenerator>
#include <QFile>
#include <QDir>
#include <QSettings>
#include <QFileInfo>
#include <QCoreApplication>
#include <QLocale>
#include "context.h"

Context::~Context()
{
    // Terminate all child processes and delete their temporary config files
    for (QProcess *process : m_childProcesses) {
        if (process->state() != QProcess::NotRunning) {
            process->terminate();
            process->waitForFinished(1000);
        }
        QString tempConfig = m_childTempConfigs.value(process);
        if (!tempConfig.isEmpty()) {
            QFile::remove(tempConfig);
        }
    }
    delete m_config;
}

void Context::init()
{
    QCommandLineOption configOption({{"c", "config"}, tr("Path to the config file."), "config"});
    QCommandLineOption presetOption({{"p", "preset"}, tr("Index of the current preset."), "preset"});
    QCommandLineOption fullScreenOption({{"f", "full-screen"}, tr("Force full-screen mode.")});
    QCommandLineOption kioskModeOption({{"k", "kiosk"}, tr("Kiosk mode functionality.")});
    QCommandLineOption logOption({{"l", "log"}, tr("Log level [%1...%2].").arg(Config::LogBeginRange).arg(Config::LogEndRange), "level"});
    QCommandLineOption auxiliaryOption(QStringList("auxiliary"), tr("Start as an auxiliary window."));

    parseCommandLineOptions({configOption,
                            presetOption,
                            fullScreenOption,
                            kioskModeOption,
                            logOption,
                            auxiliaryOption});

    m_isAuxiliary = m_commandLineParser.isSet(auxiliaryOption);

    if (m_commandLineParser.isSet(configOption)) {
        m_config = new Config(m_commandLineParser.value(configOption));
    } else {
        m_config = new Config();
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

    // Generate unique temp config file name
    QString tempConfig = QDir::tempPath() + "/cctv-viewer-aux-" 
                       + QString::number(QCoreApplication::applicationPid()) + "-" 
                       + QString::number(QRandomGenerator::global()->generate()) + ".conf";

    // Copy current configuration to the temporary file
    if (QFile::exists(mainConfigPath)) {
        QFile::copy(mainConfigPath, tempConfig);
    }

    QProcess *process = new QProcess();
    QStringList arguments;
    arguments << "-c" << tempConfig << "--auxiliary";

    connect(process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished), 
            [tempConfig, process](int exitCode, QProcess::ExitStatus exitStatus) {
        Q_UNUSED(exitCode);
        Q_UNUSED(exitStatus);
        QFile::remove(tempConfig);
        m_childTempConfigs.remove(process);
        m_childProcesses.removeOne(process);
        process->deleteLater();
    });

    m_childTempConfigs[process] = tempConfig;
    m_childProcesses.append(process);
    process->start(exePath, arguments);
}

void Context::initLanguage()
{
    QSettings settings(m_config ? m_config->fileName() : QSettings().fileName(), QSettings::IniFormat);
    QString lang = settings.value("language", "system").toString();
    
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
    QSettings settings(m_config ? m_config->fileName() : QSettings().fileName(), QSettings::IniFormat);
    return settings.value("language", "system").toString();
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
