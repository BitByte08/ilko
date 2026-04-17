#include "Application.h"

#include <QDir>
#include <QStandardPaths>
#include <QJsonObject>
#include <QDBusConnection>
#include <QDBusInterface>

#include "ProfileManager.h"
#include "NetworkWatcher.h"
#include "SwitchController.h"
#include "BatteryWatcher.h"
#include "AppConnector.h"
#include "StorageManager.h"
#include "Logger.h"

namespace ilko {

class Application::Impl
{
public:
    std::unique_ptr<ProfileManager> profileManager;
    std::unique_ptr<NetworkWatcher> networkWatcher;
    std::unique_ptr<SwitchController> switchController;
    std::unique_ptr<BatteryWatcher> batteryWatcher;
    std::unique_ptr<AppConnector> appConnector;
    std::unique_ptr<StorageManager> storageManager;

    bool screenLocked = false;
    bool onBattery = false;   // true = discharging
};

Application::Application(QObject *parent)
    : QObject(parent)
    , d(std::make_unique<Impl>())
{
    Logger::instance();
}

Application::~Application() = default;

void Application::initialize()
{
    const QString configPath = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(configPath);

    d->storageManager = std::make_unique<StorageManager>();
    d->appConnector = std::make_unique<AppConnector>();
    d->appConnector->startServer("ilko-app");

    d->profileManager = std::make_unique<ProfileManager>();
    d->profileManager->load();

    d->networkWatcher = std::make_unique<NetworkWatcher>();
    d->networkWatcher->start();

    d->batteryWatcher = std::make_unique<BatteryWatcher>();
    d->batteryWatcher->start();

    d->switchController = std::make_unique<SwitchController>(
        d->profileManager.get(),
        d->networkWatcher.get()
    );
    d->switchController->start();

    // Battery state → player control
    connect(d->batteryWatcher.get(), &BatteryWatcher::chargingChanged,
            this, &Application::onChargingChanged);

    connect(d->batteryWatcher.get(), &BatteryWatcher::stateChanged, this, [this](BatteryWatcher::BatteryState state) {
        AppConnector::Message msg;
        msg.type = AppConnector::MessageType::BatteryInfo;
        msg.sender = "daemon";
        msg.data = QJsonObject{{"state", static_cast<int>(state)}};
        d->appConnector->sendToPlugin(msg);
    });

    // NOTE: connectionStateChanged is already connected inside SwitchController's
    // constructor — do NOT add a second connection here or every signal fires twice.

    // Screen lock detection via org.freedesktop.ScreenSaver
    QDBusConnection sessionBus = QDBusConnection::sessionBus();
    sessionBus.connect(
        QStringLiteral("org.freedesktop.ScreenSaver"),
        QStringLiteral("/ScreenSaver"),
        QStringLiteral("org.freedesktop.ScreenSaver"),
        QStringLiteral("ActiveChanged"),
        this, SLOT(onScreenLockChanged(bool))
    );
    // Also try the KDE-specific path
    sessionBus.connect(
        QStringLiteral("org.kde.screensaver"),
        QStringLiteral("/ScreenSaver"),
        QStringLiteral("org.freedesktop.ScreenSaver"),
        QStringLiteral("ActiveChanged"),
        this, SLOT(onScreenLockChanged(bool))
    );

    connect(d->appConnector.get(), &AppConnector::messageReceived, this, [this](const AppConnector::Message &msg) {
        if (msg.type == AppConnector::SaveVideo || msg.type == AppConnector::ConvertVideo) {
            QString sourcePath = msg.data.value("sourcePath").toString();
            QString profileId = msg.data.value("profileId").toString();
            if (!sourcePath.isEmpty() && !profileId.isEmpty()) {
                d->storageManager->saveVideo(sourcePath, profileId);
                Logger::instance()->info("Storage", "Saved video: " + profileId);
            }
        }
    });

    // Write initial player control state
    updatePlayerControl();

    Logger::instance()->info("Application", "Initialized successfully");
}

void Application::onScreenLockChanged(bool active)
{
    d->screenLocked = active;
    updatePlayerControl();
}

void Application::onChargingChanged(bool charging)
{
    d->onBattery = !charging;
    updatePlayerControl();
}

void Application::updatePlayerControl()
{
    if (d->screenLocked) {
        ProfileManager::writePlayerControl(true, 1.0, QStringLiteral("screen_locked"));
    } else if (d->onBattery) {
        // Match macOS behaviour: throttle to 0.75x on battery, don't hard-pause
        ProfileManager::writePlayerControl(false, 0.75, QStringLiteral("battery"));
    } else {
        ProfileManager::writePlayerControl(false, 1.0);
    }
}

SwitchController *Application::switchController() const
{
    return d->switchController.get();
}

} // namespace ilko
