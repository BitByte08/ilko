#pragma once

#include <QObject>
#include <QString>

class ProfileManager;
class NetworkWatcher;

class SwitchController : public QObject
{
    Q_OBJECT

public:
    explicit SwitchController(ProfileManager *profileManager,
                          NetworkWatcher *networkWatcher,
                          QObject *parent = nullptr);
    ~SwitchController();

    void start();
    void stop();

    QString currentProfileId() const { return m_currentProfileId; }

public slots:
    void setWallpaper(const QString &profileId);
    void setWallpaperByMac(const QString &mac);

signals:
    void wallpaperChanged(const QString &profileId);
    void error(const QString &message);

private slots:
    void onNetworkChanged(const QString &gatewayMac, const QString &ssid);
    void onConnectionStateChanged(bool connected);

private:
    void applyWallpaper(const QString &wallpaperPath);
    void setDefaultWallpaper();

    ProfileManager *m_profileManager;
    NetworkWatcher *m_networkWatcher;
    QString m_currentProfileId;
    bool m_running;
};