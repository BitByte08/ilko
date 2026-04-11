using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using Ilko.Models;
using Ilko.ViewModels;
using MessageBox = System.Windows.MessageBox;

namespace Ilko.Views;

public partial class MainWindow : Window
{
    private readonly MainViewModel _vm;

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
    private const int DWMWA_WINDOW_CORNER_PREFERENCE = 33;
    private const int DWMWCP_ROUND = 2;

    public MainWindow(MainViewModel viewModel)
    {
        _vm = viewModel;
        DataContext = _vm;
        InitializeComponent();

        Loaded += (_, _) => ApplyRoundedCorners();

        _vm.PropertyChanged += (_, e) => Dispatcher.Invoke(() =>
        {
            if (e.PropertyName == nameof(MainViewModel.CurrentNetworkId))
            {
                NetworkIdText.Text = _vm.CurrentNetworkId ?? "없음";
                NetworkDot.Fill = _vm.CurrentNetworkId != null
                    ? (System.Windows.Media.Brush)FindResource("SuccessBrush")
                    : (System.Windows.Media.Brush)FindResource("TextDimBrush");
            }
            if (e.PropertyName == nameof(MainViewModel.ActiveProfile))
                ActiveProfileText.Text = _vm.ActiveProfile?.Name ?? "없음";
        });

        Closing += (_, e) => { e.Cancel = true; Hide(); };
    }

    private void ApplyRoundedCorners()
    {
        var hwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;
        int pref = DWMWCP_ROUND;
        DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, ref pref, sizeof(int));
    }

    private void OnMinimize(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void OnClose(object sender, RoutedEventArgs e) => Hide();

    private void OnRefreshClick(object sender, RoutedEventArgs e)
    {
        _vm.LocationWatcher.Refresh();
        _vm.ApplyCurrentNetwork();
    }

    private void OnAddProfileClick(object sender, RoutedEventArgs e)
        => new ProfileEditorWindow(_vm) { Owner = this }.ShowDialog();

    private void OnProfileClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.DataContext is Profile profile)
            _vm.SelectProfile(profile);
    }

    private void OnEditProfileClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is Profile profile)
            new ProfileEditorWindow(_vm, profile.Clone()) { Owner = this }.ShowDialog();
    }

    private void OnDeleteProfileClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is Profile profile)
        {
            if (MessageBox.Show($"'{profile.Name}' 프로필을 삭제할까요?", "삭제",
                    MessageBoxButton.YesNo, MessageBoxImage.Question) == MessageBoxResult.Yes)
                _vm.DeleteProfile(profile);
        }
    }
}
