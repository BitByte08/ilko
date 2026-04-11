using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
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
    public string FileName => string.IsNullOrEmpty(CurrentPath)
        ? "선택 없음"
        : System.IO.Path.GetFileName(CurrentPath);

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
        UpdateFileDisplay();

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

        // 미리보기 초기값
        UpdatePreview();

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
            var dlg = new OpenFileDialog
            {
                Title = "모니터 배경화면 선택",
                Filter = "이미지|*.jpg;*.jpeg;*.png;*.bmp|모든 파일|*.*"
            };
            if (dlg.ShowDialog() != true) return;
            item.CurrentPath = _vm.ImportWallpaper(dlg.FileName) ?? dlg.FileName;
            MonitorList.ItemsSource = null;
            MonitorList.ItemsSource = _monitorItems;
        }
    }

    /// <summary>
    /// 이미지와 동영상을 하나의 선택창에서 처리.
    /// 확장자에 따라 WallpaperPath 또는 VideoPath에 저장.
    /// </summary>
    private void OnPickFile(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog
        {
            Title = "배경화면 파일 선택",
            Filter = "이미지/동영상|*.jpg;*.jpeg;*.png;*.bmp;*.mp4;*.mov;*.avi;*.mkv;*.wmv|모든 파일|*.*"
        };
        if (dlg.ShowDialog() != true) return;

        var ext = Path.GetExtension(dlg.FileName).ToLowerInvariant();
        bool isVideo = ext is ".mp4" or ".mov" or ".avi" or ".mkv" or ".wmv";

        if (isVideo)
        {
            _profile.VideoPath = dlg.FileName;
            _profile.WallpaperPath = "";  // 동영상 선택 시 이미지 초기화
        }
        else
        {
            _profile.WallpaperPath = _vm.ImportWallpaper(dlg.FileName) ?? dlg.FileName;
            _profile.VideoPath = null;    // 이미지 선택 시 동영상 초기화
        }

        UpdateFileDisplay();
        UpdatePreview();
    }

    private void OnClearFile(object sender, RoutedEventArgs e)
    {
        _profile.WallpaperPath = "";
        _profile.VideoPath = null;
        UpdateFileDisplay();
        UpdatePreview();
    }

    private void UpdateFileDisplay()
    {
        bool hasVideo = !string.IsNullOrEmpty(_profile.VideoPath);
        bool hasImage = !string.IsNullOrEmpty(_profile.WallpaperPath);

        if (hasVideo)
        {
            FilePathText.Text = Path.GetFileName(_profile.VideoPath);
            FilePathText.Foreground = (System.Windows.Media.Brush)FindResource("TextBrush");
        }
        else if (hasImage)
        {
            FilePathText.Text = Path.GetFileName(_profile.WallpaperPath);
            FilePathText.Foreground = (System.Windows.Media.Brush)FindResource("TextBrush");
        }
        else
        {
            FilePathText.Text = "선택 없음";
            FilePathText.Foreground = (System.Windows.Media.Brush)FindResource("TextDimBrush");
        }
    }

    private void UpdatePreview()
    {
        bool hasVideo = !string.IsNullOrEmpty(_profile.VideoPath);
        bool hasImage = !string.IsNullOrEmpty(_profile.WallpaperPath)
                        && File.Exists(_profile.WallpaperPath);

        if (hasVideo)
        {
            // Windows Shell 썸네일 (File Explorer와 동일)
            PreviewImage.Source = GetShellThumbnail(_profile.VideoPath!, 640, 360);
            VideoBadge.Visibility = Visibility.Visible;
            PreviewBorder.Visibility = Visibility.Visible;
            return;
        }

        VideoBadge.Visibility = Visibility.Collapsed;

        if (!hasImage) { PreviewBorder.Visibility = Visibility.Collapsed; return; }

        var ext = Path.GetExtension(_profile.WallpaperPath).ToLowerInvariant();
        if (ext is not (".jpg" or ".jpeg" or ".png" or ".bmp"))
        {
            PreviewBorder.Visibility = Visibility.Collapsed;
            return;
        }

        try
        {
            var bmp = new BitmapImage();
            bmp.BeginInit();
            bmp.UriSource = new Uri(_profile.WallpaperPath);
            bmp.DecodePixelWidth = 800;
            bmp.CacheOption = BitmapCacheOption.OnLoad;
            bmp.EndInit();
            PreviewImage.Source = bmp;
            PreviewBorder.Visibility = Visibility.Visible;
        }
        catch { PreviewBorder.Visibility = Visibility.Collapsed; }
    }


    // ── Shell 썸네일 ──────────────────────────────────────────

    [ComImport, Guid("BCC18B79-BA16-442F-80C4-8A59C30C463B"),
     InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IShellItemImageFactory
    {
        [PreserveSig] int GetImage([In] ShellSize size, [In] uint flags, out IntPtr phbm);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ShellSize { public int cx, cy; }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode, PreserveSig = false)]
    private static extern void SHCreateItemFromParsingName(
        string pszPath, IntPtr pbc, ref Guid riid,
        [MarshalAs(UnmanagedType.Interface, IidParameterIndex = 2)] out object ppv);

    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr hObject);

    private static System.Windows.Media.ImageSource? GetShellThumbnail(string path, int w, int h)
    {
        try
        {
            var iid = typeof(IShellItemImageFactory).GUID;
            SHCreateItemFromParsingName(path, IntPtr.Zero, ref iid, out var ppv);
            if (ppv is not IShellItemImageFactory factory) return null;

            if (factory.GetImage(new ShellSize { cx = w, cy = h }, 0, out var hBitmap) != 0)
                return null;

            try
            {
                return Imaging.CreateBitmapSourceFromHBitmap(
                    hBitmap, IntPtr.Zero, Int32Rect.Empty,
                    BitmapSizeOptions.FromEmptyOptions());
            }
            finally { DeleteObject(hBitmap); }
        }
        catch { return null; }
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

        // 배경화면(이미지/동영상) 또는 모니터별 설정 중 하나 이상 필요
        bool hasWallpaper = !string.IsNullOrEmpty(_profile.WallpaperPath)
                            || !string.IsNullOrEmpty(_profile.VideoPath)
                            || _profile.MonitorWallpapers.Count > 0;
        if (!hasWallpaper)
        {
            MessageBox.Show("배경화면을 선택해주세요.", "알림",
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
