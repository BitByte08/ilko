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

        var crashLog = System.IO.Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.Desktop), "ilko_crash.log");

        AppDomain.CurrentDomain.UnhandledException += (_, ex) =>
            System.IO.File.WriteAllText(crashLog, ex.ExceptionObject?.ToString() ?? "unknown");

        DispatcherUnhandledException += (_, ex) =>
        {
            System.IO.File.WriteAllText(crashLog, ex.Exception?.ToString() ?? "unknown");
            ex.Handled = true;
        };

        try
        {
            _viewModel = new MainViewModel();
            _mainWindow = new MainWindow(_viewModel);
            _trayIcon = new TrayIcon(_viewModel, ShowMainWindow);
            ShowMainWindow();
        }
        catch (Exception ex)
        {
            System.IO.File.WriteAllText(crashLog, ex.ToString());
            Shutdown();
        }
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
