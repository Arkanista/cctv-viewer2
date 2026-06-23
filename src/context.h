#ifndef CONTEXT_H
#define CONTEXT_H

#include <QCommandLineParser>
#include <QProcess>
#include <QMap>
#include <QList>
#include <QTranslator>
#include <QQmlEngine>
#include <QUrl>
#include <QFileSystemWatcher>
#include <QVariant>

#include "config.h"

class Context : public QObject
{
    Q_OBJECT

    Q_PROPERTY(Config *config READ config CONSTANT)
    Q_PROPERTY(bool isAuxiliary READ isAuxiliary CONSTANT)
    Q_PROPERTY(int auxiliaryId READ auxiliaryId CONSTANT)

public:
    explicit Context(QObject *parent = nullptr);
    virtual ~Context();

    static void init();
    static void setEngine(QQmlEngine *engine) { m_engine = engine; }
    static void initLanguage();

    static Config *config() { return m_config; }
    static bool isAuxiliary() { return m_isAuxiliary; }
    static int auxiliaryId() { return m_auxiliaryId; }
    static bool enableLogs() { return m_enableLogs; }

    Q_INVOKABLE void setLanguage(const QString &lang);
    Q_INVOKABLE QString getLanguage() const;

    Q_INVOKABLE void startAuxiliaryProcess();

    Q_INVOKABLE void trimMemory();

    Q_INVOKABLE bool mkpath(const QString &dirPath) const;
    Q_INVOKABLE bool dirExists(const QString &dirPath) const;
    Q_INVOKABLE QString homePath() const;
    Q_INVOKABLE QUrl pathToUrl(const QString &path) const;
    Q_INVOKABLE QString selectFolder(const QString &title, const QString &initialPath) const;
    Q_INVOKABLE QString readLocalFile(const QString &filePath) const;
    Q_INVOKABLE QVariant readSetting(const QString &category, const QString &key, const QVariant &defaultValue = QVariant()) const;

signals:
    void languageChanged();
    void configFileChanged();

private:
    static void parseCommandLineOptions(const QList<QCommandLineOption> &options);

private:
    inline static Config *m_config = nullptr;
    inline static QCommandLineParser m_commandLineParser;
    inline static bool m_isAuxiliary = false;
    inline static int m_auxiliaryId = 0;
    inline static bool m_enableLogs = false;
    inline static QList<QProcess*> m_childProcesses;
    inline static QMap<QProcess*, int> m_childIds; // Track active child process IDs
    inline static QQmlEngine *m_engine = nullptr;
    inline static QTranslator *m_translator = nullptr;
    inline static QFileSystemWatcher *m_watcher = nullptr;
    inline static QList<Context*> m_instances;
    inline static QString m_language;
};

#endif // CONTEXT_H
