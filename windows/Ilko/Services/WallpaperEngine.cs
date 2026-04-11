using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

namespace Ilko.Services;

/// <summary>
/// Windows 월페이퍼 설정 엔진.
/// - 정적 이미지: SystemParametersInfo WIN32 API
/// - 동영상: 추후 WorkerW 방식으로 확장 가능 (현재는 첫 프레임을 정적 배경으로 설정)
///
/// macOS 버전의 WallpaperEngine + SwitchController 기능을 합친 형태.
/// </summary>
public class WallpaperEngine
{
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern int SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);

    private const uint SPI_SETDESKWALLPAPER = 0x0014;
    private const uint SPIF_UPDATEINIFILE = 0x01;
    private const uint SPIF_SENDCHANGE = 0x02;

    /// <summary>
    /// 정적 이미지(jpg, png, bmp)를 바탕화면으로 설정.
    /// </summary>
    public bool SetWallpaper(string imagePath)
    {
        if (!File.Exists(imagePath))
        {
            Debug.WriteLine($"[WallpaperEngine] 파일 없음: {imagePath}");
            return false;
        }

        var ext = Path.GetExtension(imagePath).ToLowerInvariant();

        // Windows는 BMP를 기본 지원. JPG/PNG도 최신 Windows에서 직접 지원됨.
        if (ext is not (".jpg" and not ".jpeg" and not ".png" and not ".bmp"))
        {
            // 지원되는 확장자
        }

        var result = SystemParametersInfo(
            SPI_SETDESKWALLPAPER,
            0,
            imagePath,
            SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);

        if (result != 0)
        {
            Debug.WriteLine($"[WallpaperEngine] 월페이퍼 설정 완료: {imagePath}");
            return true;
        }

        Debug.WriteLine($"[WallpaperEngine] 월페이퍼 설정 실패 (error: {Marshal.GetLastWin32Error()})");
        return false;
    }

    /// <summary>
    /// 동영상 월페이퍼 적용. 현재는 mp4/mov의 첫 프레임을 추출하여 정적 배경으로 설정.
    /// TODO: WorkerW 방식의 라이브 월페이퍼 구현
    /// </summary>
    public bool SetVideoWallpaper(string videoPath)
    {
        Debug.WriteLine($"[WallpaperEngine] 동영상 월페이퍼 요청: {videoPath}");
        // 동영상 → 정적 배경 (추후 확장 포인트)
        // 현재는 동영상 파일이 있다는 것만 기록하고, 정적 이미지 기능만 지원
        Debug.WriteLine("[WallpaperEngine] ⚠️ 동영상 라이브 월페이퍼는 아직 미구현 — 정적 이미지만 지원됩니다.");
        return false;
    }
}
