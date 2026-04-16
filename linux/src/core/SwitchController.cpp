#include "SwitchController.h"

#include <QProcess>
#include <QDebug>

#include "ProfileManager.h"
#include "NetworkWatcher.h"

SwitchController::SwitchController(ProfileManager *profileManager,
                                   NetworkWatcher *networkWatcher,
                                   QObject *parent)
    : QObject(parent)
    , m_profileManager(profileManager)
    , m_networkWatcher(networkWatcher)
    , m_currentProfileId()
    , m_running(false)
{
    if (m_networkWatcher) {
        connect(m_networkWatcher, &NetworkWatcher::networkChanged,
                this, &SwitchController::onNetworkChanged);
        connect(m_networkWatcher, &NetworkWatcher::connectionStateChanged,
                this, &SwitchController::onConnectionStateChanged);
    }
}

SwitchController::~SwitchController() = default;

void SwitchController::start()
{
    if (m_running) return;
    m_running = true;

    if (m_networkWatcher->isConnected()) {
        setWallpaperByMac(m_networkWatcher->currentGatewayMac());
    } else {
        setDefaultWallpaper();
    }
}

void SwitchController::stop()
{
    m_running = false;
}

void SwitchController::onNetworkChanged(const QString &gatewayMac, const QString &ssid)
{
    Q_UNUSED(ssid);
    setWallpaperByMac(gatewayMac);
}

void SwitchController::onConnectionStateChanged(bool connected)
{
    if (!connected) {
        setDefaultWallpaper();
    } else if (m_networkWatcher->isConnected()) {
        setWallpaperByMac(m_networkWatcher->currentGatewayMac());
    }
}

void SwitchController::setWallpaperByMac(const QString &mac)
{
    if (!m_profileManager) return;

    Profile profile = m_profileManager->profileForMac(mac);
    if (profile.id.isEmpty()) {
        setDefaultWallpaper();
        return;
    }

    setWallpaper(profile.id);
}

void SwitchController::setWallpaper(const QString &profileId)
{
    if (!m_profileManager) return;

    const QList<Profile> profiles = m_profileManager->profiles();
    for (const Profile &profile : profiles) {
        if (profile.id == profileId) {
            applyWallpaper(profile.wallpaperPath);
            m_currentProfileId = profileId;
            emit wallpaperChanged(profileId);
            return;
        }
    }

    emit error(QStringLiteral("Profile not found: %1").arg(profileId));
}

void SwitchController::setDefaultWallpaper()
{
    if (!m_profileManager) return;

    Profile profile = m_profileManager->defaultProfile();
    if (profile.wallpaperPath.isEmpty()) {
        return;
    }

    applyWallpaper(profile.wallpaperPath);
    m_currentProfileId = profile.id;
    emit wallpaperChanged(profile.id);
}

void SwitchController::applyWallpaper(const QString &wallpaperPath)
{
    if (wallpaperPath.isEmpty()) {
        return;
    }

    QProcess process;
    process.start("gsettings", QStringList{
        "set", "org.gnome.desktop.background", "picture-uri",
        "file://" + wallpaperPath
    });
    process.waitForFinished(1000);

    qDebug() << "Wallpaper set to:" << wallpaperPath;
}