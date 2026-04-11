using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Ilko.Views;

public partial class VideoWallpaperHost : Window
{
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int n);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int n, int v);
    private const int GWL_EXSTYLE     = -20;
    private const int WS_EX_NOACTIVATE = 0x08000000;
    private const int WS_EX_TOOLWINDOW = 0x00000080;

    public VideoWallpaperHost(string videoPath)
    {
        InitializeComponent();

        Loaded += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            var ex = GetWindowLong(hwnd, GWL_EXSTYLE);
            SetWindowLong(hwnd, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);
        };

        Video.Source = new Uri(videoPath);
        Video.Play();
    }

    private void OnMediaEnded(object sender, RoutedEventArgs e)
    {
        Video.Position = TimeSpan.Zero;
        Video.Play();
    }
}
