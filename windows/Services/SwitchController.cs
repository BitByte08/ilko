using System.Diagnostics;
using Ilko.Models;

namespace Ilko.Services;

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

    public void Apply(Profile profile)
    {
        if (profile.Id == ActiveProfile?.Id) return;
        ApplyProfile(profile);
    }

    public void ForceApply(Profile profile) => ApplyProfile(profile);

    public void ApplyCurrentNetwork()
    {
        var profile = _profileManager.ProfileFor(_locationWatcher.CurrentGatewayMAC);
        if (profile == null) return;
        ApplyProfile(profile);
    }

    private void OnNetworkChange(string? mac)
    {
        var profile = _profileManager.ProfileFor(mac);
        if (profile == null || profile.Id == ActiveProfile?.Id) return;
        ApplyProfile(profile);
    }

    private void ApplyProfile(Profile profile)
    {
        Debug.WriteLine($"[SwitchController] 적용: {profile.Name}");
        ActiveProfile = profile;
        _profileManager.ActiveProfileId = profile.Id;
        ActiveProfileChanged?.Invoke(profile);
        _engine.ApplyProfile(profile);
    }
}
