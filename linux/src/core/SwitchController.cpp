#include "SwitchController.h"

#include <QDebug>

#include "ProfileManager.h"
#include "NetworkWatcher.h"
#include "WallpaperDBusService.h"

SwitchController::SwitchController(ProfileManager *profileManager,
                                   NetworkWatcher *networkWatcher,
                                   QObject *parent)
    : QObject(parent)
    , m_profileManager(profileManager)
    , m_networkWatcher(networkWatcher)
    , m_currentProfileId()
    , m_running(false)
    , m_dbusService(nullptr)
{
    if (m_networkWatcher) {
        connect(m_networkWatcher, &NetworkWatcher::networkChanged,
                this, &SwitchController::onNetworkChanged);
        connect(m_networkWatcher, &NetworkWatcher::connectionStateChanged,
                this, &SwitchController::onConnectionChanged);
    }

    m_dbusService = new ilko::WallpaperDBusService(this);
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

void SwitchController::onConnectionChanged(bool connected)
{
    if (!connected) {
        setDefaultWallpaper();
    }
    // on connect: networkChanged is always emitted alongside this signal,
    // so onNetworkChanged handles the wallpaper switch — no double-apply here.
}

void SwitchController::onLowBattery(bool low)
{
    qDebug() << "Battery low state:" << low;
}

void SwitchController::setWallpaperByMac(const QString &mac)
{
    if (!m_profileManager) return;

    m_profileManager->load();

    if (mac.isEmpty()) {
        setDefaultWallpaper();
        return;
    }

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
            m_currentProfileId = profileId;
            applyWallpaper(profile.wallpaperPath);
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

    m_currentProfileId = profile.id;
    applyWallpaper(profile.wallpaperPath);
    emit wallpaperChanged(profile.id);
}

void SwitchController::applyWallpaper(const QString &wallpaperPath)
{
    if (wallpaperPath.isEmpty()) return;

    // Conversion is the UI's responsibility (ProfileEditDialog).
    // The daemon just applies the path as-is.
    ProfileManager::setCurrentWallpaper(wallpaperPath, m_currentProfileId);
    if (m_dbusService) {
        m_dbusService->emitWallpaperChanged(wallpaperPath, m_currentProfileId);
    }
    qDebug() << "Wallpaper applied:" << wallpaperPath;
}
