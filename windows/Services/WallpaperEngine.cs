using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using Ilko.Models;
using WpfApp = System.Windows.Application;

namespace Ilko.Services;

public class WallpaperEngine : IDisposable
{
    // ── IDesktopWallpaper COM ──────────────────────────────────────────────
    [ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
    [ClassInterface(ClassInterfaceType.None)]
    private class DesktopWallpaperClass { }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT { public int Left, Top, Right, Bottom; }

    [ComImport]
    [Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDesktopWallpaper
    {
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitorID,
                          [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        [return: MarshalAs(UnmanagedType.LPWStr)]
        string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitorID);
        [return: MarshalAs(UnmanagedType.LPWStr)]
        string GetMonitorDevicePathAt(uint monitorIndex);
        uint GetMonitorDevicePathCount();
        void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID,
                            out RECT displayRect);
        void SetBackgroundColor(uint color);
        uint GetBackgroundColor();
        void SetPosition(WallpaperPosition position);
        WallpaperPosition GetPosition();
    }

    private static readonly string TempDir =
        Path.Combine(Path.GetTempPath(), "ilko_wallpaper");

    private readonly VideoWallpaperService _videoService = new();
    private bool _disposed;

    // ── 공개 API ──────────────────────────────────────────────────────────

    public List<MonitorInfo> GetMonitors()
    {
        try
        {
            var dw = (IDesktopWallpaper)new DesktopWallpaperClass();
            var count = dw.GetMonitorDevicePathCount();
            var result = new List<MonitorInfo>();
            for (uint i = 0; i < count; i++)
                result.Add(new MonitorInfo
                {
                    Index = (int)i,
                    DevicePath = dw.GetMonitorDevicePathAt(i),
                    FriendlyName = $"모니터 {i + 1}"
                });
            return result;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[WallpaperEngine] GetMonitors 실패: {ex.Message}");
            return [];
        }
    }

    /// <summary>
    /// 프로필 적용.
    ///
    /// VideoPath가 있으면:
    ///   - 정적 폴백(WallpaperPath)을 IDesktopWallpaper에 먼저 설정 (앱 꺼져도 유지)
    ///   - VideoWallpaperService로 WorkerW에 영상 재생
    ///
    /// VideoPath가 없으면:
    ///   - 영상 중단 후 IDesktopWallpaper로 정적 이미지 적용
    /// </summary>
    public void ApplyProfile(Profile profile)
    {
        bool hasVideo = !string.IsNullOrEmpty(profile.VideoPath)
                        && File.Exists(profile.VideoPath);

        // 1. 정적 폴백 항상 설정 (영상 켜져 있어도 뒤에 깔림 → 꺼지면 바로 보임)
        ApplyStaticWallpaper(profile);

        // 2. 영상 처리
        if (hasVideo)
        {
            WpfApp.Current?.Dispatcher.Invoke(() =>
                _videoService.Play(profile.VideoPath!));
        }
        else
        {
            if (_videoService.IsActive)
                WpfApp.Current?.Dispatcher.Invoke(() => _videoService.Stop());
        }
    }

    public WallpaperPosition GetCurrentPosition()
    {
        try
        {
            return ((IDesktopWallpaper)new DesktopWallpaperClass()).GetPosition();
        }
        catch { return WallpaperPosition.Fill; }
    }

    public void StopVideo()
    {
        if (_videoService.IsActive)
            WpfApp.Current?.Dispatcher.Invoke(() => _videoService.Stop());
    }

    // ── 정적 이미지 적용 (IDesktopWallpaper) ─────────────────────────────

    private void ApplyStaticWallpaper(Profile profile)
    {
        // WallpaperPath가 없으면 정적 설정 생략
        if (string.IsNullOrEmpty(profile.WallpaperPath)
            && profile.MonitorWallpapers.Count == 0)
            return;

        try
        {
            var dw = (IDesktopWallpaper)new DesktopWallpaperClass();
            dw.SetPosition(profile.Position);

            var count = dw.GetMonitorDevicePathCount();
            if (count == 0) return;

            for (uint i = 0; i < count; i++)
            {
                var monitorPath = dw.GetMonitorDevicePathAt(i);
                profile.MonitorWallpapers.TryGetValue(monitorPath, out var imgPath);
                imgPath ??= profile.WallpaperPath;

                if (string.IsNullOrEmpty(imgPath) || !File.Exists(imgPath)) continue;

                // Center 모드 + 오프셋
                if (profile.Position == WallpaperPosition.Center
                    && (profile.OffsetX != 0 || profile.OffsetY != 0))
                {
                    dw.GetMonitorRECT(monitorPath, out var rect);
                    int w = rect.Right - rect.Left;
                    int h = rect.Bottom - rect.Top;
                    if (w > 0 && h > 0)
                        imgPath = CreateOffsetBitmap(imgPath, w, h,
                                      profile.OffsetX, profile.OffsetY) ?? imgPath;
                }

                dw.SetWallpaper(monitorPath, imgPath);
                Debug.WriteLine($"[WallpaperEngine] 모니터 {i + 1}: {Path.GetFileName(imgPath)}");
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[WallpaperEngine] ApplyStaticWallpaper 실패: {ex.Message}");
        }
    }

    // ── Center 오프셋 비트맵 생성 ─────────────────────────────────────────

    private static string? CreateOffsetBitmap(string srcPath, int canvasW, int canvasH,
                                               int offsetX, int offsetY)
    {
        try
        {
            Directory.CreateDirectory(TempDir);
            using var src = Image.FromFile(srcPath);
            using var bmp = new System.Drawing.Bitmap(canvasW, canvasH);
            using var g = Graphics.FromImage(bmp);
            g.Clear(Color.Black);
            int x = (canvasW - src.Width) / 2 + offsetX;
            int y = (canvasH - src.Height) / 2 + offsetY;
            g.DrawImage(src, x, y, src.Width, src.Height);
            var dest = Path.Combine(TempDir,
                $"{Path.GetFileNameWithoutExtension(srcPath)}_off.bmp");
            bmp.Save(dest, ImageFormat.Bmp);
            return dest;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[WallpaperEngine] CreateOffsetBitmap 실패: {ex.Message}");
            return null;
        }
    }

    // ── IDisposable ───────────────────────────────────────────────────────
    public void Dispose()
    {
        if (_disposed) return;
        _videoService.Dispose();
        _disposed = true;
    }
}
