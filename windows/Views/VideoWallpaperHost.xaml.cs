using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Ilko.Views;

public partial class VideoWallpaperHost : Window
{
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr h, int n);
    [DllImport("user32.dll")] static extern int SetWindowLong(IntPtr h, int n, int v);
    [DllImport("user32.dll")] static extern IntPtr SetParent(IntPtr child, IntPtr parent);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool SetWindowPos(IntPtr hwnd, IntPtr after,
        int x, int y, int cx, int cy, uint flags);

    private const int  GWL_EXSTYLE      = -20;
    private const int  WS_EX_NOACTIVATE = 0x08000000;
    private const int  WS_EX_TOOLWINDOW = 0x00000080;
    private const uint SWP_NOACTIVATE   = 0x0010;
    private const uint SWP_NOZORDER     = 0x0004;
    private const uint SWP_FRAMECHANGED = 0x0020;

    private readonly string _videoPath;

    public VideoWallpaperHost(string videoPath)
    {
        _videoPath = videoPath;
        InitializeComponent();
        Loaded += OnLoaded;
    }

    /// <summary>
    /// Show() 전에 호출. HWND를 생성하고 WorkerW 자식으로 배치한 뒤
    /// Show()로 처음부터 올바른 위치에서 렌더링되도록 한다.
    /// </summary>
    public void AttachToWorkerW(IntPtr workerW, System.Drawing.Rectangle bounds)
    {
        // HWND 생성 (Show() 없이)
        var helper = new WindowInteropHelper(this);
        helper.EnsureHandle();
        var hwnd = helper.Handle;

        // 포커스/Alt+Tab 방지
        var ex = GetWindowLong(hwnd, GWL_EXSTYLE);
        SetWindowLong(hwnd, GWL_EXSTYLE, ex | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW);

        // Show() 전에 WorkerW 자식으로 등록 → WPF가 처음부터 이 위치에서 렌더링
        SetParent(hwnd, workerW);
        SetWindowPos(hwnd, IntPtr.Zero,
            bounds.X, bounds.Y, bounds.Width, bounds.Height,
            SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED);
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        Video.Source = new Uri(_videoPath, UriKind.Absolute);
        Video.Play();
    }

    private void OnMediaEnded(object sender, RoutedEventArgs e)
    {
        Video.Position = TimeSpan.Zero;
        Video.Play();
    }

    private void OnMediaFailed(object sender, ExceptionRoutedEventArgs e)
        => Debug.WriteLine($"[VideoWallpaperHost] 재생 실패: {e.ErrorException?.Message}");
}
