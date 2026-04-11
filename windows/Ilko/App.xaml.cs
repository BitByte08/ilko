using System.Windows;
using Ilko.ViewModels;
using Ilko.Views;

namespace Ilko;

public partial class App : System.Windows.Application
{
    private TrayIcon? _trayIcon;
    private MainViewModel? _viewModel;
    private MainWindow? _mainWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _viewModel = new MainViewModel();
        _mainWindow = new MainWindow(_viewModel);

        // 시스템 트레이 아이콘 설정
        _trayIcon = new TrayIcon(_viewModel, ShowMainWindow);

        // 첫 실행 시 메인 윈도우 표시
        ShowMainWindow();
    }

    private void ShowMainWindow()
    {
        if (_mainWindow == null) return;
        _mainWindow.Show();
        _mainWindow.Activate();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayIcon?.Dispose();
        _viewModel?.Shutdown();
        base.OnExit(e);
    }
}
