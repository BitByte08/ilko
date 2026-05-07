#include <QApplication>
#include <QLockFile>
#include <QStandardPaths>
#include <QMessageBox>

#include "ui/MainWindow.h"
#include "core/Application.h"
#include "core/SwitchController.h"

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    app.setApplicationName("ILKO");
    app.setApplicationVersion("1.0.0");
    app.setDesktopFileName("ilko");
    app.setQuitOnLastWindowClosed(false);

    // Single-instance guard
    QLockFile lockFile(QStandardPaths::writableLocation(QStandardPaths::TempLocation) + "/ilko.lock");
    lockFile.setStaleLockTime(0);
    if (!lockFile.tryLock(200)) {
        QMessageBox::information(nullptr, "ILKO", "ILKO is already running.\nCheck the system tray.");
        return 0;
    }

    // Start daemon services (network watcher, switch controller, D-Bus service, etc.)
    ilko::Application daemon;
    daemon.initialize();

    MainWindow window;
    // Re-apply wallpaper whenever the UI saves a profile edit
    QObject::connect(&window, &MainWindow::profileSaved,
                     daemon.switchController(), &SwitchController::reapplyCurrentProfile);
    window.show();

    // 이번 실행에서 처음으로 하이브리드 GPU를 감지해 절전 설정을 적용한 경우 알림
    if (daemon.wasGpuPowerSavingApplied())
        window.notifyHybridGpuApplied();

    return app.exec();
}
