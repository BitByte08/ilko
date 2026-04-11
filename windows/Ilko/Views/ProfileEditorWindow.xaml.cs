using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media.Imaging;
using RadioButton = System.Windows.Controls.RadioButton;
using Ilko.Models;
using Ilko.ViewModels;
using MessageBox = System.Windows.MessageBox;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;

namespace Ilko.Views;

/// <summary>모니터 항목 — MonitorList에 바인딩되는 뷰모델.</summary>
public class MonitorItem
{
    public MonitorInfo Monitor { get; }
    public string FriendlyName => Monitor.FriendlyName;
    public string? CurrentPath { get; set; }

    public MonitorItem(MonitorInfo monitor, string? path)
    {
        Monitor = monitor;
        CurrentPath = path;
    }
}

public partial class ProfileEditorWindow : Window
{
    private readonly MainViewModel _vm;
    private readonly Profile _profile;
    private readonly bool _isNew;
    private readonly List<MonitorItem> _monitorItems = [];

    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

    public ProfileEditorWindow(MainViewModel vm, Profile? existing = null)
    {
        _vm = vm;
        _isNew = existing == null;
        _profile = existing ?? new Profile
        {
            Name = "",
            GatewayMAC = vm.CurrentNetworkId,
            WallpaperPath = ""
        };

        InitializeComponent();

        Loaded += (_, _) =>
        {
            var hwnd = new System.Windows.Interop.WindowInteropHelper(this).Handle;
            int pref = 2;
            DwmSetWindowAttribute(hwnd, 33, ref pref, sizeof(int));
        };

        TitleText.Text = _isNew ? "프로필 추가" : "프로필 편집";
        NameBox.Text = _profile.Name;
        MacText.Text = _profile.GatewayMAC ?? "없음 = 기본 프로필";
        UpdateDefaultWallpaperDisplay();

        // 기본 프로필이면 이름/네트워크 변경 불가
        if (_profile.GatewayMAC == null && !_isNew)
        {
            NameBox.IsEnabled = false;
            UseCurrentBtn.IsEnabled = false;
        }

        // 모니터 목록 구성
        var monitors = _vm.Engine.GetMonitors();
        foreach (var m in monitors)
        {
            _profile.MonitorWallpapers.TryGetValue(m.DevicePath, out var path);
            _monitorItems.Add(new MonitorItem(m, path));
        }
        MonitorList.ItemsSource = _monitorItems;

        // 정렬 방식 라디오 버튼 구성
        BuildPositionRadios();

        // 오프셋 초기값
        SliderX.Value = _profile.OffsetX;
        SliderY.Value = _profile.OffsetY;
        OffsetXLabel.Text = _profile.OffsetX.ToString();
        OffsetYLabel.Text = _profile.OffsetY.ToString();

        // Center 모드면 오프셋 섹션 표시
        if (_profile.Position == WallpaperPosition.Center)
            OffsetSection.Visibility = Visibility.Visible;
    }

    // ── 정렬 방식 ─────────────────────────────────────────────

    private void BuildPositionRadios()
    {
        var positions = new[]
        {
            (WallpaperPosition.Fill,    "채우기"),
            (WallpaperPosition.Fit,     "맞추기"),
            (WallpaperPosition.Stretch, "늘리기"),
            (WallpaperPosition.Center,  "가운데"),
            (WallpaperPosition.Tile,    "타일"),
        };

        PositionPanel.Children.Clear();
        foreach (var (pos, label) in positions)
        {
            var rb = new RadioButton
            {
                Content   = label,
                Tag       = pos,
                IsChecked = _profile.Position == pos,
                GroupName = "WallpaperPosition",
                Margin    = new Thickness(0, 0, 16, 4),
            };
            rb.Checked += OnPositionChecked;
            PositionPanel.Children.Add(rb);
        }
    }

    private void OnPositionChecked(object sender, RoutedEventArgs e)
    {
        if (sender is RadioButton { Tag: WallpaperPosition pos })
        {
            _profile.Position = pos;
            OffsetSection.Visibility = pos == WallpaperPosition.Center
                ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void OnOffsetXChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        => OffsetXLabel.Text = ((int)e.NewValue).ToString();

    private void OnOffsetYChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
        => OffsetYLabel.Text = ((int)e.NewValue).ToString();

    // ── 네트워크 ──────────────────────────────────────────────

    private void OnUseCurrentNetwork(object sender, RoutedEventArgs e)
    {
        var mac = _vm.LocationWatcher.GetCurrentNetworkId();
        if (mac != null)
        {
            _profile.GatewayMAC = mac;
            MacText.Text = mac;
        }
        else
        {
            MessageBox.Show("현재 네트워크를 감지할 수 없습니다.", "알림",
                MessageBoxButton.OK, MessageBoxImage.Information);
        }
    }

    // ── 월페이퍼 선택 ─────────────────────────────────────────

    private void OnPickMonitorFile(object sender, RoutedEventArgs e)
    {
        if (sender is FrameworkElement fe && fe.Tag is MonitorItem item)
        {
            var path = PickImageFile();
            if (path == null) return;
            item.CurrentPath = _vm.ImportWallpaper(path) ?? path;
            MonitorList.ItemsSource = null;
            MonitorList.ItemsSource = _monitorItems;
            UpdatePreview(item.CurrentPath);
        }
    }

    private void OnPickDefaultFile(object sender, RoutedEventArgs e)
    {
        var path = PickImageFile();
        if (path == null) return;
        _profile.WallpaperPath = _vm.ImportWallpaper(path) ?? path;
        UpdateDefaultWallpaperDisplay();
        UpdatePreview(_profile.WallpaperPath);
    }

    private string? PickImageFile()
    {
        var dlg = new OpenFileDialog
        {
            Title = "월페이퍼 파일 선택",
            Filter = "이미지|*.jpg;*.jpeg;*.png;*.bmp|모든 파일|*.*"
        };
        return dlg.ShowDialog() == true ? dlg.FileName : null;
    }

    private void UpdateDefaultWallpaperDisplay()
    {
        DefaultWallpaperText.Text = string.IsNullOrEmpty(_profile.WallpaperPath)
            ? "선택 없음"
            : Path.GetFileName(_profile.WallpaperPath);
        DefaultWallpaperText.Foreground = string.IsNullOrEmpty(_profile.WallpaperPath)
            ? (System.Windows.Media.Brush)FindResource("TextDimBrush")
            : (System.Windows.Media.Brush)FindResource("TextBrush");
    }

    private void UpdatePreview(string? path)
    {
        if (string.IsNullOrEmpty(path) || !File.Exists(path)) return;
        var ext = Path.GetExtension(path).ToLowerInvariant();
        if (ext is not (".jpg" or ".jpeg" or ".png" or ".bmp")) return;
        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.UriSource = new Uri(path);
            bmp.DecodePixelWidth = 800;
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.EndInit();
            PreviewImage.Source = bmp;
            PreviewBorder.Visibility = Visibility.Visible;
        }
        catch { }
    }

    // ── 저장 / 취소 ───────────────────────────────────────────

    private void OnSave(object sender, RoutedEventArgs e)
    {
        _profile.Name = NameBox.Text.Trim();
        if (string.IsNullOrEmpty(_profile.Name))
        {
            MessageBox.Show("프로필 이름을 입력해주세요.", "알림",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        // 모니터별 경로 저장
        _profile.MonitorWallpapers.Clear();
        foreach (var item in _monitorItems)
        {
            if (!string.IsNullOrEmpty(item.CurrentPath))
                _profile.MonitorWallpapers[item.Monitor.DevicePath] = item.CurrentPath;
        }

        // 오프셋 저장
        _profile.OffsetX = (int)SliderX.Value;
        _profile.OffsetY = (int)SliderY.Value;

        // 최소 하나의 월페이퍼가 있어야 함
        if (string.IsNullOrEmpty(_profile.WallpaperPath) && _profile.MonitorWallpapers.Count == 0)
        {
            MessageBox.Show("월페이퍼를 하나 이상 선택해주세요.", "알림",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        _vm.SaveProfile(_profile);
        DialogResult = true;
        Close();
    }

    private void OnCancel(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }
}
