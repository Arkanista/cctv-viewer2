#ifndef CONTEXT_H
#define CONTEXT_H

#include <QCommandLineParser>
#include <QProcess>
#include <QMap>
#include <QList>
#include <QTranslator>
#include <QQmlEngine>
#include <QUrl>

#include "config.h"

class Context : public QObject
{
    Q_OBJECT

    Q_PROPERTY(Config *config READ config CONSTANT)
    Q_PROPERTY(bool isAuxiliary READ isAuxiliary CONSTANT)

public:
    explicit Context(QObject *parent = nullptr) : QObject(parent) { }
    virtual ~Context();

    static void init();
    static void setEngine(QQmlEngine *engine) { m_engine = engine; }
    static void initLanguage();

    static Config *config() { return m_config; }
    static bool isAuxiliary() { return m_isAuxiliary; }

    Q_INVOKABLE void setLanguage(const QString &lang);
    Q_INVOKABLE QString getLanguage() const;

    Q_INVOKABLE void startAuxiliaryProcess();

    Q_INVOKABLE bool mkpath(const QString &dirPath) const;
    Q_INVOKABLE bool dirExists(const QString &dirPath) const;
    Q_INVOKABLE QString homePath() const;
    Q_INVOKABLE QUrl pathToUrl(const QString &path) const;

signals:
    void languageChanged();

private:
    static void parseCommandLineOptions(const QList<QCommandLineOption> &options);

private:
    inline static Config *m_config = nullptr;
    inline static QCommandLineParser m_commandLineParser;
    inline static bool m_isAuxiliary = false;
    inline static QList<QProcess*> m_childProcesses;
    inline static QMap<QProcess*, QString> m_childTempConfigs;
    inline static QQmlEngine *m_engine = nullptr;
    inline static QTranslator *m_translator = nullptr;
};

#endif // CONTEXT_H
