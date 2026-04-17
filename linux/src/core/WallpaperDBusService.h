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

signals:
    void WallpaperChanged(const QString &wallpaperPath, const QString &profileId);

public:
    void emitWallpaperChanged(const QString &wallpaperPath, const QString &profileId);

private:
    QString m_currentWallpaper;
    QString m_currentProfileId;
    bool registerOnDBus();
};

} // namespace ilko
