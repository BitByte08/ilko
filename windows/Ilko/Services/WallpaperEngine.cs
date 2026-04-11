using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using Ilko.Models;

namespace Ilko.Services;

/// <summary>
/// IDesktopWallpaper COM 인터페이스를 통해 모니터별 배경화면을 설정한다.
/// </summary>
public class WallpaperEngine
{
    // ── COM 인터페이스 ──────────────────────────────────────────
    [ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
    [ClassInterface(ClassInterfaceType.None)]
    private class DesktopWallpaperClass { }

    [ComImport]
    [Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IDesktopWallpaper
    {
        // vtable[3]
        void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitorID,
                          [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
        // vtable[4]
        [return: MarshalAs(UnmanagedType.LPWStr)]
        string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string? monitorID);
        // vtable[5]
        [return: MarshalAs(UnmanagedType.LPWStr)]
        string GetMonitorDevicePathAt(uint monitorIndex);
        // vtable[6]
        uint GetMonitorDevicePathCount();
    }

    // ── 공개 API ────────────────────────────────────────────────

    /// <summary>현재 연결된 모니터 목록 반환.</summary>
    public List<MonitorInfo> GetMonitors()
    {
        try
        {
            var dw = (IDesktopWallpaper)new DesktopWallpaperClass();
            var count = dw.GetMonitorDevicePathCount();
            var result = new List<MonitorInfo>();
            for (uint i = 0; i < count; i++)
            {
                result.Add(new MonitorInfo
                {
                    Index = (int)i,
                    DevicePath = dw.GetMonitorDevicePathAt(i),
                    FriendlyName = $"모니터 {i + 1}"
                });
            }
            return result;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[WallpaperEngine] GetMonitors 실패: {ex.Message}");
            return [];
        }
    }

    /// <summary>
    /// 프로필의 MonitorWallpapers를 적용.
    /// MonitorWallpapers가 비어있으면 WallpaperPath를 전체에 적용.
    /// </summary>
    public void ApplyProfile(Profile profile)
    {
        if (profile.MonitorWallpapers.Count > 0)
        {
            var monitors = GetMonitors();
            foreach (var monitor in monitors)
            {
                var path = profile.MonitorWallpapers.GetValueOrDefault(monitor.DevicePath)
                           ?? profile.WallpaperPath;
                if (!string.IsNullOrEmpty(path))
                    SetForMonitor(monitor.DevicePath, path);
            }
        }
        else if (!string.IsNullOrEmpty(profile.WallpaperPath))
        {
            SetForAll(profile.WallpaperPath);
        }
    }

    /// <summary>특정 모니터에 이미지 설정.</summary>
    public bool SetForMonitor(string monitorDevicePath, string imagePath)
    {
        if (!File.Exists(imagePath)) return false;
        try
        {
            var dw = (IDesktopWallpaper)new DesktopWallpaperClass();
            dw.SetWallpaper(monitorDevicePath, imagePath);
            Debug.WriteLine($"[WallpaperEngine] {Path.GetFileName(imagePath)} → {monitorDevicePath[..Math.Min(30, monitorDevicePath.Length)]}...");
            return true;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[WallpaperEngine] SetForMonitor 실패: {ex.Message}");
            return false;
        }
    }

    /// <summary>전체 모니터에 같은 이미지 설정 (null monitorID = all).</summary>
    public bool SetForAll(string imagePath)
    {
        if (!File.Exists(imagePath)) return false;
        try
        {
            var dw = (IDesktopWallpaper)new DesktopWallpaperClass();
            dw.SetWallpaper(null, imagePath);
            Debug.WriteLine($"[WallpaperEngine] 전체 모니터: {Path.GetFileName(imagePath)}");
            return true;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[WallpaperEngine] SetForAll 실패: {ex.Message}");
            return false;
        }
    }
}
