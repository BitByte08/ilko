using System.Windows;
using System.Windows.Input;
using Ilko.Models;
using Ilko.ViewModels;
using MessageBox = System.Windows.MessageBox;

namespace Ilko.Views;

public partial class MainWindow : Window
{
    private readonly MainViewModel _vm;

    public MainWindow(MainViewModel viewModel)
    {
        _vm = viewModel;
        DataContext = _vm;
        InitializeComponent();

        // 상태 바 바인딩
        _vm.PropertyChanged += (_, e) =>
        {
            Dispatcher.Invoke(() =>
            {
                if (e.PropertyName == nameof(MainViewModel.CurrentNetworkId))
                    NetworkIdText.Text = _vm.CurrentNetworkId ?? "없음";
                if (e.PropertyName == nameof(MainViewModel.ActiveProfile))
                    ActiveProfileText.Text = _vm.ActiveProfile?.Name ?? "없음";
            });
        };

        // 닫기 → 트레이로 숨기기
        Closing += (_, e) =>
        {
            e.Cancel = true;
            Hide();
        };
    }

    private void OnRefreshClick(object sender, RoutedEventArgs e)
    {
        _vm.LocationWatcher.Refresh();
        _vm.ApplyCurrentNetwork();
    }

    private void OnAddProfileClick(object sender, RoutedEventArgs e)
    {
        var editor = new ProfileEditorWindow(_vm) { Owner = this };
        editor.ShowDialog();
    }

    private void OnProfileClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.DataContext is Profile profile)
            _vm.SelectProfile(profile);
    }

    private void OnEditProfileClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is Profile profile)
        {
            var editor = new ProfileEditorWindow(_vm, profile.Clone()) { Owner = this };
            editor.ShowDialog();
        }
    }

    private void OnDeleteProfileClick(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is Profile profile)
        {
            var r = MessageBox.Show(
                $"'{profile.Name}' 프로필을 삭제하시겠습니까?",
                "프로필 삭제", MessageBoxButton.YesNo, MessageBoxImage.Question);
            if (r == MessageBoxResult.Yes)
                _vm.DeleteProfile(profile);
        }
    }
}
