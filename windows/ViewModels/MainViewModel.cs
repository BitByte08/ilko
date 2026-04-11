using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using Ilko.Models;
using Ilko.Services;

namespace Ilko.ViewModels;

public class MainViewModel : INotifyPropertyChanged
{
    private readonly ProfileManager _profileManager;
    private readonly LocationWatcher _locationWatcher;
    private readonly SwitchController _switchController;
    private readonly WallpaperEngine _engine;

    private Profile? _activeProfile;
    private string? _currentNetworkId;

    public ObservableCollection<Profile> Profiles { get; } = [];

    public Profile? ActiveProfile
    {
        get => _activeProfile;
        set
        {
            _activeProfile = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(ActiveProfileId));
        }
    }

    /// <summary>현재 활성 프로필 ID — 타일 강조에 사용.</summary>
    public string? ActiveProfileId => _activeProfile?.Id;

    public string? CurrentNetworkId
    {
        get => _currentNetworkId;
        set { _currentNetworkId = value; OnPropertyChanged(); }
    }

    // ── Services ───────────────────────────────────────────────
    public ProfileManager ProfileManager => _profileManager;
    public LocationWatcher LocationWatcher => _locationWatcher;
    public SwitchController SwitchController => _switchController;
    public WallpaperEngine Engine => _engine;

    // ── ctor ───────────────────────────────────────────────────
    public MainViewModel()
    {
        _profileManager = new ProfileManager();
        _locationWatcher = new LocationWatcher();
        _engine = new WallpaperEngine();
        _switchController = new SwitchController(_profileManager, _locationWatcher, _engine);

        _switchController.ActiveProfileChanged += p => { ActiveProfile = p; };
        _locationWatcher.GatewayMACChanged += mac => { CurrentNetworkId = mac; };
        _profileManager.ProfilesChanged += RefreshProfiles;

        RefreshProfiles();
        _locationWatcher.Start();
    }

    // ── Commands ───────────────────────────────────────────────
    public void RefreshProfiles()
    {
        Profiles.Clear();
        foreach (var p in _profileManager.Profiles)
            Profiles.Add(p);
    }

    public void SelectProfile(Profile profile) => _switchController.Apply(profile);
    public void ApplyCurrentNetwork() => _switchController.ApplyCurrentNetwork();

    public void SaveProfile(Profile profile)
    {
        var isNew = !_profileManager.Profiles.Any(p => p.Id == profile.Id);
        if (isNew) _profileManager.Add(profile);
        else       _profileManager.Update(profile);
        _switchController.ForceApply(profile);
    }

    public void DeleteProfile(Profile profile)
    {
        var isActive = ActiveProfile?.Id == profile.Id;
        _profileManager.Delete(profile.Id);
        if (isActive)
        {
            var fallback = _profileManager.Profiles.FirstOrDefault(p => p.GatewayMAC == null);
            if (fallback != null) _switchController.Apply(fallback);
        }
    }

    public string? ImportWallpaper(string sourcePath)
    {
        try { return _profileManager.ImportWallpaper(sourcePath); }
        catch { return sourcePath; }
    }

    public void Shutdown()
    {
        _locationWatcher.Stop();
        _locationWatcher.Dispose();
        _engine.Dispose(); // 영상 중단 (정적 폴백은 이미 설정돼 있음)
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
