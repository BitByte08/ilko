#include "SwitchController.h"

#include <QProcess>
#include <QFile>
#include <QFileInfo>
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
    } else if (m_networkWatcher->isConnected()) {
        setWallpaperByMac(m_networkWatcher->currentGatewayMac());
    }
}

void SwitchController::setWallpaperByMac(const QString &mac)
{
    if (!m_profileManager) return;

    // 프로필 리로드 (UI에서 변경했을 수 있음)
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

    int targetFps = 30;
    for (const Profile &p : m_profileManager->profiles()) {
        if (p.id == m_currentProfileId) {
            targetFps = p.targetFps > 0 ? p.targetFps : 30;
            break;
        }
    }

    QFileInfo fi(wallpaperPath);
    QStringList videoExts = {"mp4", "webm", "mov", "avi", "mkv", "m4v", "flv", "wmv"};
    bool needsEncoding = videoExts.contains(fi.suffix().toLower()) && !wallpaperPath.contains("_h265");

    if (needsEncoding) {
        QProcess *ffmpeg = new QProcess(this);
        QString outputPath = wallpaperPath.left(wallpaperPath.lastIndexOf('.')) + "_h265.mp4";

        QStringList args;
        args << "-i" << wallpaperPath
             << "-c:v" << "libx265"
             << "-preset" << "faster"
             << "-crf" << "28"
             << "-r" << QString::number(targetFps)
             << "-c:a" << "aac"
             << "-b:a" << "128k"
             << "-threads" << "0"
             << "-y"
             << outputPath;

        connect(ffmpeg, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, [this, ffmpeg, wallpaperPath, outputPath](int exitCode, QProcess::ExitStatus) {
            if (exitCode == 0 && QFile::exists(outputPath)) {
                QFile::remove(wallpaperPath);
                QFile::rename(outputPath, wallpaperPath);
                qDebug() << "H.265 conversion done:" << wallpaperPath;
            } else {
                qWarning() << "H.265 conversion failed, using original file:" << wallpaperPath;
                if (QFile::exists(outputPath)) QFile::remove(outputPath);
            }
            // Notify only after encoding completes (success or failure)
            ProfileManager::setCurrentWallpaper(wallpaperPath, m_currentProfileId);
            if (m_dbusService) {
                m_dbusService->emitWallpaperChanged(wallpaperPath, m_currentProfileId);
            }
            ffmpeg->deleteLater();
        });

        ffmpeg->start("ffmpeg", args);
        qDebug() << "Started H.265 conversion in background:" << wallpaperPath;
        return;
    }

    // No encoding needed — notify immediately
    ProfileManager::setCurrentWallpaper(wallpaperPath, m_currentProfileId);
    if (m_dbusService) {
        m_dbusService->emitWallpaperChanged(wallpaperPath, m_currentProfileId);
    }
    qDebug() << "Wallpaper set to:" << wallpaperPath;
}