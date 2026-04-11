namespace Ilko.Models;

/// <summary>연결된 모니터 정보.</summary>
public class MonitorInfo
{
    public string DevicePath { get; set; } = "";
    public string FriendlyName { get; set; } = "";
    public int Index { get; set; }
}
