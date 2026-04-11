using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using Ilko.Models;

namespace Ilko.Services;

public class WallpaperEngine
{
    // ── COM ─────────────────────────────────────────────────────
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
                          [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);        // vtable[3]
        [return: MarshalAs(UnmanagedType.LPWStr)]
        string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitorID);    // vtable[4]
        [return: MarshalAs(UnmanagedType.LPWStr)]
        string GetMonitorDevicePathAt(uint monitorIndex);                             // vtable[5]
        uint GetMonitorDevicePathCount();                                             // vtable[6]
        void GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID,
                            out RECT displayRect);                                    // vtable[7]
        void SetBackgroundColor(uint color);                                          // vtable[8]
        uint GetBackgroundColor();                                                    // vtable[9]
        void SetPosition(WallpaperPosition position);                                 // vtable[10]
        WallpaperPosition GetPosition();                                              // vtable[11]
    }

    private static readonly string TempDir =
        Path.Combine(Path.GetTempPath(), "ilko_wallpaper");

    // ── 공개 API ────────────────────────────────────────────────

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

    public void ApplyProfile(Profile profile)
    {
        try
        {
            var dw = (IDesktopWallpaper)new DesktopWallpaperClass();

            // 1. 정렬 방식 설정
            dw.SetPosition(profile.Position);

            // 2. 모니터별 월페이퍼 적용
            var count = dw.GetMonitorDevicePathCount();
            if (count == 0) return;

            for (uint i = 0; i < count; i++)
            {
                var monitorPath = dw.GetMonitorDevicePathAt(i);

                // 모니터별 경로 → 없으면 기본 경로
                profile.MonitorWallpapers.TryGetValue(monitorPath, out var imgPath);
                imgPath ??= profile.WallpaperPath;
                if (string.IsNullOrEmpty(imgPath) || !File.Exists(imgPath)) continue;

                // 오프셋 처리 (Center 모드 + 오프셋 있을 때)
                if (profile.Position == WallpaperPosition.Center
                    && (profile.OffsetX != 0 || profile.OffsetY != 0))
                {
                    dw.GetMonitorRECT(monitorPath, out var rect);
                    int w = rect.Right - rect.Left;
                    int h = rect.Bottom - rect.Top;
                    if (w > 0 && h > 0)
                        imgPath = CreateOffsetBitmap(imgPath, w, h, profile.OffsetX, profile.OffsetY)
                                  ?? imgPath;
                }

                dw.SetWallpaper(monitorPath, imgPath);
                Debug.WriteLine($"[WallpaperEngine] 모니터 {i + 1}: {Path.GetFileName(imgPath)}");
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[WallpaperEngine] ApplyProfile 실패: {ex.Message}");
        }
    }

    public WallpaperPosition GetCurrentPosition()
    {
        try
        {
            var dw = (IDesktopWallpaper)new DesktopWallpaperClass();
            return dw.GetPosition();
        }
        catch { return WallpaperPosition.Fill; }
    }

    // ── 내부 유틸 ───────────────────────────────────────────────

    /// <summary>
    /// 지정한 화면 크기의 캔버스 위에 이미지를 center + offset 위치에 그린 BMP를 반환.
    /// </summary>
    private static string? CreateOffsetBitmap(string srcPath, int canvasW, int canvasH,
                                               int offsetX, int offsetY)
    {
        try
        {
            Directory.CreateDirectory(TempDir);
            using var src = Image.FromFile(srcPath);
            using var bmp = new Bitmap(canvasW, canvasH);
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
}
