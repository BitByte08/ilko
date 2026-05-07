#pragma once

#include <QObject>
#include <QString>
#include <QDBusConnection>

namespace ilko {

class WallpaperDBusService : public QObject
{
    Q_OBJECT
    Q_CLASSINFO("D-Bus Interface", "org.bssm.ilko.WallpaperService")

public:
    explicit WallpaperDBusService(QObject *parent = nullptr);
    ~WallpaperDBusService();

public slots:
    Q_SCRIPTABLE QString getCurrentWallpaper() const;
    Q_SCRIPTABLE QString getCurrentProfileId() const;
    Q_SCRIPTABLE void setWallpaper(const QString &wallpaperPath, const QString &profileId);
    Q_SCRIPTABLE int getBatteryPercentage() const;
    Q_SCRIPTABLE bool isBatteryCharging() const;
    Q_SCRIPTABLE bool isBatteryLow() const;

signals:
    void WallpaperChanged(const QString &wallpaperPath, const QString &profileId);
    void BatteryChanged(int percentage, bool charging, bool low);

public:
    void emitWallpaperChanged(const QString &wallpaperPath, const QString &profileId);
    void emitBatteryChanged(int percentage, bool charging, bool low);

private:
    QString m_currentWallpaper;
    QString m_currentProfileId;
    int m_batteryPercentage;
    bool m_batteryCharging;
    bool registerOnDBus();
};

} // namespace ilko
