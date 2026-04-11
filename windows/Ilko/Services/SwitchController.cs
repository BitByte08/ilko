using System.Diagnostics;
using System.IO;
using Ilko.Models;

namespace Ilko.Services;

/// <summary>
/// 네트워크 변경 구독 → 매칭 프로필 → 월페이퍼 적용.
/// macOS 버전의 SwitchController.swift 와 동일 기능.
/// </summary>
public class SwitchController
{
    private readonly ProfileManager _profileManager;
    private readonly LocationWatcher _locationWatcher;
    private readonly WallpaperEngine _engine;

    public Profile? ActiveProfile { get; private set; }

    public event Action<Profile?>? ActiveProfileChanged;

    public SwitchController(ProfileManager profileManager, LocationWatcher locationWatcher, WallpaperEngine engine)
    {
        _profileManager = profileManager;
        _locationWatcher = locationWatcher;
        _engine = engine;

        _locationWatcher.GatewayMACChanged += OnNetworkChange;
    }

    /// <summary>수동으로 프로필 전환.</summary>
    public void Apply(Profile profile) => ApplyProfile(profile);

    /// <summary>현재 네트워크에 맞는 프로필을 강제 적용.</summary>
    public void ApplyCurrentNetwork()
    {
        var mac = _locationWatcher.CurrentGatewayMAC;
        var profile = _profileManager.ProfileFor(mac);
        if (profile == null)
        {
            Debug.WriteLine($"[SwitchController] 매칭 프로필 없음 (mac: {mac ?? "null"})");
            return;
        }
        Debug.WriteLine($"[SwitchController] 강제 적용: {profile.Name}");
        ApplyProfile(profile);
    }

    private void OnNetworkChange(string? mac)
    {
        Debug.WriteLine($"[SwitchController] 네트워크 변경 감지: {mac ?? "null"}");
        var profile = _profileManager.ProfileFor(mac);
        if (profile == null)
        {
            Debug.WriteLine("[SwitchController] 매칭 프로필 없음");
            return;
        }
        Debug.WriteLine($"[SwitchController] 매칭: {profile.Name}");
        if (profile.Id == ActiveProfile?.Id)
        {
            Debug.WriteLine("[SwitchController] 이미 활성 프로필, 건너뜀");
            return;
        }
        ApplyProfile(profile);
    }

    private void ApplyProfile(Profile profile)
    {
        Debug.WriteLine($"[SwitchController] 프로필 적용: {profile.Name}");
        ActiveProfile = profile;
        _profileManager.ActiveProfileId = profile.Id;
        ActiveProfileChanged?.Invoke(profile);

        var path = profile.WallpaperPath;
        if (string.IsNullOrEmpty(path))
        {
            Debug.WriteLine("[SwitchController] 월페이퍼 경로 비어있음");
            return;
        }

        var ext = Path.GetExtension(path).ToLowerInvariant();
        switch (ext)
        {
            case ".jpg" or ".jpeg" or ".png" or ".bmp":
                _engine.SetWallpaper(path);
                break;
            case ".mp4" or ".mov":
                _engine.SetVideoWallpaper(path);
                break;
        }
    }
}
