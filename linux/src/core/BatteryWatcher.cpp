#include "BatteryWatcher.h"

#include <QProcess>
#include <QFile>
#include <QDBusConnection>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>
#include <QDBusReply>

namespace ilko {

BatteryWatcher::BatteryWatcher(QObject *parent)
    : QObject(parent)
    , m_timer(new QTimer(this))
    , m_percentage(0)
    , m_state(Unknown)
    , m_isPresent(false)
    , m_wasLow(false)
    , m_upowerInterface(nullptr)
{
    connect(m_timer, &QTimer::timeout, this, &BatteryWatcher::checkBattery);
}

BatteryWatcher::~BatteryWatcher() = default;

void BatteryWatcher::start()
{
    QDBusConnection dbus = QDBusConnection::systemBus();
    if (dbus.isConnected()) {
        m_upowerInterface = new QDBusInterface(
            "org.freedesktop.UPower",
            "/org/freedesktop/UPower",
            "org.freedesktop.DBus.Properties",
            dbus,
            this
        );
    }

    checkBattery();
    m_timer->start(30000);
}

void BatteryWatcher::stop()
{
    m_timer->stop();
}

void BatteryWatcher::checkBattery()
{
    int prevPercentage = m_percentage;
    BatteryState prevState = m_state;

    if (m_upowerInterface && m_upowerInterface->isValid()) {
        updateFromUPower();
    } else {
        updateFromSysfs();
    }

    if (m_percentage != prevPercentage) {
        emit percentageChanged(m_percentage);
    }
    if (m_state != prevState) {
        emit stateChanged(m_state);
        emit chargingChanged(m_state == Charging);
    }

    bool isLow = m_percentage > 0 && m_percentage <= 15 && m_state != Charging;
    if (isLow != m_wasLow) {
        m_wasLow = isLow;
        emit lowBattery(isLow);
    }

    if (m_percentage != prevPercentage || m_state != prevState) {
        writeStateFile();
    }
}

void BatteryWatcher::writeStateFile()
{
    QString homeDir = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
    QString ilkoDir = homeDir + "/.ilko";
    QDir().mkpath(ilkoDir);

    QJsonObject obj;
    obj["percentage"] = m_percentage;
    obj["charging"] = (m_state == Charging);
    obj["low"] = (m_percentage > 0 && m_percentage <= 15 && m_state != Charging);

    QJsonDocument doc(obj);
    QFile file(ilkoDir + "/battery_state.json");
    if (file.open(QIODevice::WriteOnly)) {
        file.write(doc.toJson());
        file.close();
    }
}

void BatteryWatcher::updateFromUPower()
{
    QDBusMessage reply = m_upowerInterface->call("Get",
        "org.freedesktop.UPower", "RemainingTime");

    if (reply.type() == QDBusMessage::ReplyMessage) {
        QDBusVariant var = reply.arguments().first().value<QDBusVariant>();
        QVariant value = var.variant();

        QDBusMessage propsReply = m_upowerInterface->call("GetAll",
            "org.freedesktop.UPower");

        if (propsReply.type() == QDBusMessage::ReplyMessage) {
            QVariantMap map = qdbus_cast<QVariantMap>(propsReply.arguments().first());
            if (map.contains("Percentage")) {
                m_percentage = map.value("Percentage").toInt();
            }
            if (map.contains("State")) {
                QString state = map.value("State").toString();
                if (state == "charging") m_state = Charging;
                else if (state == "discharging") m_state = Discharging;
                else if (state == "fully-charged") m_state = Full;
                else m_state = Unknown;
            }
            m_isPresent = true;
        }
    }
}

void BatteryWatcher::updateFromSysfs()
{
    QFile capacityFile("/sys/class/power_supply/BAT0/capacity");
    if (capacityFile.open(QIODevice::ReadOnly)) {
        QString data = capacityFile.readAll().trimmed();
        m_percentage = data.toInt();
        capacityFile.close();
        m_isPresent = m_percentage >= 0;
    }

    QFile statusFile("/sys/class/power_supply/BAT0/status");
    if (statusFile.open(QIODevice::ReadOnly)) {
        QString status = statusFile.readAll().trimmed();
        if (status == "Charging") m_state = Charging;
        else if (status == "Discharging") m_state = Discharging;
        else if (status == "Full") m_state = Full;
        else m_state = Unknown;
        statusFile.close();
    }
}

}