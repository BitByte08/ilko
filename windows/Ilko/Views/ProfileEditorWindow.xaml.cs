using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;
using Ilko.Models;
using Ilko.ViewModels;
using MessageBox = System.Windows.MessageBox;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;

namespace Ilko.Views;

public partial class ProfileEditorWindow : Window
{
    private readonly MainViewModel _vm;
    private readonly Profile _profile;
    private readonly bool _isNew;

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

        TitleText.Text = _isNew ? "프로필 추가" : "프로필 편집";
        NameBox.Text = _profile.Name;
        MacText.Text = _profile.GatewayMAC ?? "없음 = 기본 프로필";
        UpdateWallpaperDisplay();

        // 기본 프로필이면 네트워크 변경 비활성화
        if (_profile.GatewayMAC == null && !_isNew)
        {
            UseCurrentBtn.IsEnabled = false;
            NameBox.IsEnabled = false;
        }
    }

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

    private void OnPickFile(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "월페이퍼 파일 선택",
            Filter = "이미지/동영상|*.jpg;*.jpeg;*.png;*.bmp;*.mp4;*.mov|모든 파일|*.*"
        };

        if (dialog.ShowDialog() == true)
        {
            var imported = _vm.ImportWallpaper(dialog.FileName);
            _profile.WallpaperPath = imported ?? dialog.FileName;
            UpdateWallpaperDisplay();
        }
    }

    private void UpdateWallpaperDisplay()
    {
        var path = _profile.WallpaperPath;
        WallpaperText.Text = string.IsNullOrEmpty(path) ? "파일 없음" : Path.GetFileName(path);

        // 이미지 미리보기
        if (!string.IsNullOrEmpty(path) && File.Exists(path))
        {
            var ext = Path.GetExtension(path).ToLowerInvariant();
            if (ext is ".jpg" or ".jpeg" or ".png" or ".bmp")
            {
                try
                {
                    var bitmap = new BitmapImage();
                    bitmap.BeginInit();
                    bitmap.UriSource = new Uri(path);
                    bitmap.DecodePixelWidth = 800;
                    bitmap.CacheOption = BitmapCacheOption.OnLoad;
                    bitmap.EndInit();
                    PreviewImage.Source = bitmap;
                }
                catch
                {
                    PreviewImage.Source = null;
                }
            }
            else
            {
                PreviewImage.Source = null;
            }
        }
        else
        {
            PreviewImage.Source = null;
        }
    }

    private void OnSave(object sender, RoutedEventArgs e)
    {
        _profile.Name = NameBox.Text.Trim();

        if (string.IsNullOrEmpty(_profile.Name))
        {
            MessageBox.Show("프로필 이름을 입력해주세요.", "알림",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (string.IsNullOrEmpty(_profile.WallpaperPath))
        {
            MessageBox.Show("월페이퍼 파일을 선택해주세요.", "알림",
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
