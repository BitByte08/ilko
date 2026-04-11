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

    public Profile Clone() => new()
    {
        Id = Id,
        Name = Name,
        GatewayMAC = GatewayMAC,
        WallpaperPath = WallpaperPath,
        MonitorWallpapers = new Dictionary<string, string>(MonitorWallpapers)
    };
}
