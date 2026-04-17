#include "WallpaperDBusService.h"

#include <QDBusConnection>
#include <QDBusError>
#include <QDebug>

namespace ilko {

WallpaperDBusService::WallpaperDBusService(QObject *parent)
    : QObject(parent)
    , m_currentWallpaper()
    , m_currentProfileId()
    , m_batteryPercentage(100)
    , m_batteryCharging(false)
{
    registerOnDBus();
}

WallpaperDBusService::~WallpaperDBusService() = default;

QString WallpaperDBusService::getCurrentWallpaper() const
{
    return m_currentWallpaper;
}

QString WallpaperDBusService::getCurrentProfileId() const
{
    return m_currentProfileId;
}

void WallpaperDBusService::setWallpaper(const QString &wallpaperPath, const QString &profileId)
{
    m_currentWallpaper = wallpaperPath;
    m_currentProfileId = profileId;
    emit WallpaperChanged(wallpaperPath, profileId);
}

void WallpaperDBusService::emitWallpaperChanged(const QString &wallpaperPath, const QString &profileId)
{
    m_currentWallpaper = wallpaperPath;
    m_currentProfileId = profileId;
    emit WallpaperChanged(wallpaperPath, profileId);
}

int WallpaperDBusService::getBatteryPercentage() const
{
    return m_batteryPercentage;
}

bool WallpaperDBusService::isBatteryCharging() const
{
    return m_batteryCharging;
}

bool WallpaperDBusService::isBatteryLow() const
{
    return m_batteryPercentage > 0 && m_batteryPercentage <= 15 && !m_batteryCharging;
}

void WallpaperDBusService::emitBatteryChanged(int percentage, bool charging, bool low)
{
    m_batteryPercentage = percentage;
    m_batteryCharging = charging;
    emit BatteryChanged(percentage, charging, low);
}

bool WallpaperDBusService::registerOnDBus()
{
    QDBusConnection dbus = QDBusConnection::sessionBus();
    
    if (!dbus.isConnected()) {
        qWarning() << "Cannot connect to D-Bus session bus";
        return false;
    }
    
    if (!dbus.registerObject("/org/bssm/ilko/WallpaperService", this)) {
        qWarning() << "Cannot register D-Bus object:" << dbus.lastError().message();
        return false;
    }
    
    if (!dbus.registerService("org.bssm.ilko.WallpaperService")) {
        qWarning() << "Cannot register D-Bus service:" << dbus.lastError().message();
        return false;
    }
    
    qDebug() << "WallpaperDBusService registered on D-Bus";
    return true;
}

} // namespace ilko
