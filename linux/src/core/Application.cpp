#include "Application.h"

#include <QDir>
#include <QStandardPaths>

#include "ProfileManager.h"
#include "NetworkWatcher.h"
#include "SwitchController.h"

namespace ilko {

class Application::Impl
{
public:
    std::unique_ptr<ProfileManager> profileManager;
    std::unique_ptr<NetworkWatcher> networkWatcher;
    std::unique_ptr<SwitchController> switchController;
};

Application::Application(QObject *parent)
    : QObject(parent)
    , d(std::make_unique<Impl>())
{
}

Application::~Application() = default;

void Application::initialize()
{
    const QString configPath = QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation);
    QDir().mkpath(configPath);

    d->profileManager = std::make_unique<ProfileManager>();
    d->profileManager->load();

    d->networkWatcher = std::make_unique<NetworkWatcher>();
    d->networkWatcher->start();

    d->switchController = std::make_unique<SwitchController>(
        d->profileManager.get(),
        d->networkWatcher.get()
    );
    d->switchController->start();
}

SwitchController *Application::switchController() const
{
    return d->switchController.get();
}

}