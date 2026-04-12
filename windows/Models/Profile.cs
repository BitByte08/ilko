using System.Text.Json.Serialization;

namespace Ilko.Models;

/// <summary>
/// 게이트웨이 MAC 하나에 월페이퍼를 매핑하는 프로필.
/// MonitorWallpapers가 비어있으면 WallpaperPath를 전체 모니터에 적용.
/// </summary>
public class Profile
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = Guid.NewGuid().ToString();

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("gatewayMAC")]
    public string? GatewayMAC { get; set; }

    /// <summary>모든 모니터 공통 월페이퍼 (MonitorWallpapers 없을 때 fallback).</summary>
    [JsonPropertyName("wallpaperPath")]
    public string WallpaperPath { get; set; } = "";

    /// <summary>모니터별 월페이퍼: DevicePath → imagePath.</summary>
    [JsonPropertyName("monitorWallpapers")]
    public Dictionary<string, string> MonitorWallpapers { get; set; } = [];

    /// <summary>배경화면 정렬 방식.</summary>
    [JsonPropertyName("position")]
    public WallpaperPosition Position { get; set; } = WallpaperPosition.Fill;

    /// <summary>가운데(Center) 모드에서 X 오프셋 (픽셀).</summary>
    [JsonPropertyName("offsetX")]
    public int OffsetX { get; set; } = 0;

    /// <summary>가운데(Center) 모드에서 Y 오프셋 (픽셀).</summary>
    [JsonPropertyName("offsetY")]
    public int OffsetY { get; set; } = 0;

    /// <summary>
    /// 동영상 배경화면 경로 (MP4 등).
    /// 설정 시 앱 실행 중에는 WorkerW 레이어에서 영상이 재생되고,
    /// 앱 종료 후에는 WallpaperPath 정적 이미지가 폴백으로 유지됨.
    /// </summary>
    [JsonPropertyName("videoPath")]
    public string? VideoPath { get; set; }

    public Profile Clone() => new()
    {
        Id = Id,
        Name = Name,
        GatewayMAC = GatewayMAC,
        WallpaperPath = WallpaperPath,
        MonitorWallpapers = new Dictionary<string, string>(MonitorWallpapers),
        Position = Position,
        OffsetX = OffsetX,
        OffsetY = OffsetY,
        VideoPath = VideoPath,
    };
}
