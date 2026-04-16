#include "NetworkWatcher.h"

#include <QProcess>
#include <QRegularExpression>
#include <QDebug>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>

NetworkWatcher::NetworkWatcher(QObject *parent)
    : QObject(parent)
    , m_nmIface(nullptr)
    , m_timer(new QTimer(this))
    , m_currentGatewayMac()
    , m_currentSsid()
    , m_isConnected(false)
    , m_running(false)
{
    connect(m_timer, &QTimer::timeout, this, &NetworkWatcher::checkNetwork);
    
    QDBusConnection dbus = QDBusConnection::systemBus();
    if (dbus.isConnected()) {
        m_nmIface = new QDBusInterface(
            "org.freedesktop.NetworkManager",
            "/org/freedesktop/NetworkManager",
            "org.freedesktop.DBus.Properties",
            dbus,
            this
        );
        
        if (m_nmIface->isValid()) {
            dbus.connect(
                "org.freedesktop.NetworkManager",
                "/org/freedesktop/NetworkManager",
                "org.freedesktop.DBus.Properties",
                "PropertiesChanged",
                this,
                SLOT(onNMPropertiesChanged(QString,QVariantMap,QStringList))
            );
        }
    }
}

NetworkWatcher::~NetworkWatcher() = default;

void NetworkWatcher::start()
{
    if (m_running) return;
    m_running = true;
    checkNetwork();
    m_timer->start(10000);  // 10초로 늘림 (D-Bus 시그널이 주요 변경 감지)
}

void NetworkWatcher::stop()
{
    m_running = false;
    m_timer->stop();
}

void NetworkWatcher::onNMPropertiesChanged(const QString &interface, const QVariantMap &changed, const QStringList &invalidated)
{
    Q_UNUSED(invalidated);
    
    if (interface == "org.freedesktop.NetworkManager") {
        if (changed.contains("PrimaryConnection") || changed.contains("ActiveConnections")) {
            checkNetwork();
        }
    }
}

QString NetworkWatcher::getGatewayMac()
{
    QProcess process;
    process.start("ip", QStringList{"neigh", "show", "default"}, QIODevice::ReadOnly);
    
    if (!process.waitForStarted(500)) {
        return QString{};
    }
    
    process.closeWriteChannel();
    
    QString output;
    if (process.waitForReadyRead(1000)) {
        output = process.readAllStandardOutput();
    }
    process.kill();
    process.waitForFinished(500);

    QString mac;
    if (parseArpOutput(output, mac)) {
        return mac.toLower();
    }
    return QString{};
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
    QString oldGatewayMac = m_currentGatewayMac;
    bool wasConnected = m_isConnected;

    QString gatewayMac = getGatewayMac();

    m_isConnected = !gatewayMac.isEmpty();

    if (m_isConnected != wasConnected) {
        emit connectionStateChanged(m_isConnected);
    }

    if (!gatewayMac.isEmpty() && gatewayMac != oldGatewayMac) {
        m_currentGatewayMac = gatewayMac;
        emit networkChanged(gatewayMac, m_currentSsid);
    }
    
    if (m_isConnected && gatewayMac.isEmpty()) {
        m_currentGatewayMac.clear();
    }
}