#include "NetworkWatcher.h"

#include <QProcess>
#include <QRegularExpression>
#include <QDebug>

NetworkWatcher::NetworkWatcher(QObject *parent)
    : QObject(parent)
    , m_timer(new QTimer(this))
    , m_currentGatewayMac()
    , m_currentSsid()
    , m_isConnected(false)
    , m_running(false)
{
    connect(m_timer, &QTimer::timeout, this, &NetworkWatcher::checkNetwork);
}

NetworkWatcher::~NetworkWatcher() = default;

void NetworkWatcher::start()
{
    if (m_running) return;
    m_running = true;
    checkNetwork();
    m_timer->start(5000);
}

void NetworkWatcher::stop()
{
    m_running = false;
    m_timer->stop();
}

QString NetworkWatcher::getGatewayMac()
{
    QProcess process;
    process.start("ip", QStringList{"neigh", "show", "default"});
    process.waitForFinished(2000);

    if (process.exitCode() != 0) {
        return QString{};
    }

    QString output = process.readAllStandardOutput();
    QString mac;

    if (!parseArpOutput(output, mac)) {
        return QString{};
    }

    return mac.toLower();
}

bool NetworkWatcher::parseArpOutput(const QString &output, QString &mac)
{
    QRegularExpression re("\\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\\b");
    QRegularExpressionMatch match = re.match(output);

    if (match.hasMatch()) {
        mac = match.captured();
        return true;
    }

    return false;
}

void NetworkWatcher::checkNetwork()
{
    QString gatewayMac = getGatewayMac();
    bool wasConnected = m_isConnected;

    m_isConnected = !gatewayMac.isEmpty();
    m_currentGatewayMac = gatewayMac;

    if (m_isConnected != wasConnected) {
        emit connectionStateChanged(m_isConnected);
    }

    if (m_isConnected && gatewayMac != m_currentGatewayMac) {
        emit networkChanged(gatewayMac, m_currentSsid);
    }
}