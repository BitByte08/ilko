using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using Ilko.Views;

namespace Ilko.Services;

/// <summary>
/// Wallpaper Engine 방식으로 WorkerW 레이어에 영상을 재생.
///
/// 동작 원리:
///   1. SendMessageTimeout(Progman, 0x052C) → WorkerW 스폰
///   2. SHELLDLL_DefView 뒤에 오는 WorkerW 핸들 획득
///   3. VideoWallpaperHost(WPF+MediaElement)를 WorkerW의 자식으로 SetParent
///   4. SetWindowPos로 각 모니터 물리 픽셀에 배치
///
/// 앱 종료 시 IDesktopWallpaper로 정적 폴백이 이미 설정돼 있으므로
/// Stop()만 호출하면 바탕화면이 정상 복원됨.
/// </summary>
public class VideoWallpaperService : IDisposable
{
    // ── P/Invoke ───────────────────────────────────────────────────────────
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    static extern IntPtr FindWindow(string cls, string? title);

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    static extern IntPtr FindWindowEx(IntPtr parent, IntPtr after, string cls, string? title);

    [DllImport("user32.dll", SetLastError = true)]
    static extern IntPtr SetParent(IntPtr child, IntPtr newParent);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    static extern bool SetWindowPos(IntPtr hwnd, IntPtr after,
        int x, int y, int cx, int cy, uint flags);

    [DllImport("user32.dll")]
    static extern IntPtr SendMessageTimeout(IntPtr hwnd, uint msg,
        IntPtr wp, IntPtr lp, uint flags, uint timeout, out IntPtr result);

    [DllImport("user32.dll")]
    static extern bool EnumWindows(EnumWindowsProc fn, IntPtr lp);
    delegate bool EnumWindowsProc(IntPtr hwnd, IntPtr lp);

    private const uint SWP_NOACTIVATE = 0x0010;
    private const uint SWP_NOZORDER   = 0x0004;

    // ── 상태 ──────────────────────────────────────────────────────────────
    private readonly List<VideoWallpaperHost> _hosts = [];
    private bool _disposed;

    public bool IsActive => _hosts.Count > 0;

    // ── 공개 API ──────────────────────────────────────────────────────────

    /// <summary>영상 재생 시작. 모든 모니터에 각각 VideoWallpaperHost를 생성.</summary>
    public void Play(string videoPath)
    {
        Stop();

        var workerW = GetOrCreateWorkerW();
        if (workerW == IntPtr.Zero)
        {
            Debug.WriteLine("[VideoWallpaperService] WorkerW 획득 실패");
            return;
        }

        foreach (System.Windows.Forms.Screen screen in System.Windows.Forms.Screen.AllScreens)
        {
            var b = screen.Bounds; // 물리 픽셀

            var host = new VideoWallpaperHost(videoPath);

            // HWND를 Show() 전에 생성해 두면 SetParent 시 깜빡임 없음
            var helper = new WindowInteropHelper(host);
            helper.EnsureHandle();

            SetParent(helper.Handle, workerW);
            SetWindowPos(helper.Handle, IntPtr.Zero, b.X, b.Y, b.Width, b.Height,
                         SWP_NOACTIVATE | SWP_NOZORDER);

            host.Show();
            _hosts.Add(host);
        }

        Debug.WriteLine($"[VideoWallpaperService] 재생 시작: {System.IO.Path.GetFileName(videoPath)} × {_hosts.Count}개 모니터");
    }

    /// <summary>재생 중단 및 모든 호스트 창 닫기.</summary>
    public void Stop()
    {
        foreach (var host in _hosts)
        {
            try
            {
                if (!host.Dispatcher.HasShutdownStarted)
                    host.Dispatcher.Invoke(host.Close);
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[VideoWallpaperService] 호스트 닫기 실패: {ex.Message}");
            }
        }
        _hosts.Clear();
    }

    // ── WorkerW 핸들 획득 ─────────────────────────────────────────────────

    /// <summary>
    /// Progman에 0x052C 메시지를 보내 WorkerW를 스폰하고,
    /// SHELLDLL_DefView 다음에 오는 WorkerW 핸들을 반환.
    /// </summary>
    private static IntPtr GetOrCreateWorkerW()
    {
        var progman = FindWindow("Progman", null);
        if (progman == IntPtr.Zero) return IntPtr.Zero;

        // WorkerW 스폰 (이미 있어도 무해)
        SendMessageTimeout(progman, 0x052C, IntPtr.Zero, IntPtr.Zero, 0, 1000, out _);

        IntPtr workerW = IntPtr.Zero;
        EnumWindows((hwnd, _) =>
        {
            // SHELLDLL_DefView를 자식으로 가진 창 뒤에 WorkerW가 있음
            var defView = FindWindowEx(hwnd, IntPtr.Zero, "SHELLDLL_DefView", null);
            if (defView != IntPtr.Zero)
                workerW = FindWindowEx(IntPtr.Zero, hwnd, "WorkerW", null);
            return true; // 계속 열거
        }, IntPtr.Zero);

        return workerW;
    }

    // ── IDisposable ───────────────────────────────────────────────────────
    public void Dispose()
    {
        if (_disposed) return;
        Stop();
        _disposed = true;
    }
}
