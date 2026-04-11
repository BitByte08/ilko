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
    private Profile? _editingProfile;
    private bool _isEditing;

    public ObservableCollection<Profile> Profiles { get; } = [];

    public Profile? ActiveProfile
    {
        get => _activeProfile;
        set { _activeProfile = value; OnPropertyChanged(); }
    }

    public string? CurrentNetworkId
    {
        get => _currentNetworkId;
        set { _currentNetworkId = value; OnPropertyChanged(); }
    }

    public Profile? EditingProfile
    {
        get => _editingProfile;
        set { _editingProfile = value; OnPropertyChanged(); }
    }

    public bool IsEditing
    {
        get => _isEditing;
        set { _isEditing = value; OnPropertyChanged(); }
    }

    // Services exposed for View binding
    public ProfileManager ProfileManager => _profileManager;
    public LocationWatcher LocationWatcher => _locationWatcher;
    public SwitchController SwitchController => _switchController;

    public MainViewModel()
    {
        _profileManager = new ProfileManager();
        _locationWatcher = new LocationWatcher();
        _engine = new WallpaperEngine();
        _switchController = new SwitchController(_profileManager, _locationWatcher, _engine);

        _switchController.ActiveProfileChanged += p =>
        {
            ActiveProfile = p;
        };

        _locationWatcher.GatewayMACChanged += mac =>
        {
            CurrentNetworkId = mac;
        };

        _profileManager.ProfilesChanged += RefreshProfiles;

        RefreshProfiles();
        _locationWatcher.Start();
    }

    public void RefreshProfiles()
    {
        Profiles.Clear();
        foreach (var p in _profileManager.Profiles)
            Profiles.Add(p);
    }

    public void SelectProfile(Profile profile)
    {
        _switchController.Apply(profile);
    }

    public void ApplyCurrentNetwork()
    {
        _switchController.ApplyCurrentNetwork();
    }

    public void AddProfile()
    {
        EditingProfile = new Profile
        {
            Name = "",
            GatewayMAC = _locationWatcher.CurrentGatewayMAC,
            WallpaperPath = ""
        };
        IsEditing = true;
    }

    public void EditProfile(Profile profile)
    {
        EditingProfile = profile.Clone();
        IsEditing = true;
    }

    public void SaveProfile(Profile profile)
    {
        var isNew = !_profileManager.Profiles.Any(p => p.Id == profile.Id);
        if (isNew)
            _profileManager.Add(profile);
        else
            _profileManager.Update(profile);

        // 저장 후 항상 즉시 적용
        _switchController.ForceApply(profile);

        IsEditing = false;
        EditingProfile = null;
    }

    public void CancelEdit()
    {
        IsEditing = false;
        EditingProfile = null;
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
        try
        {
            return _profileManager.ImportWallpaper(sourcePath);
        }
        catch
        {
            return sourcePath;
        }
    }

    public void Shutdown()
    {
        _locationWatcher.Stop();
        _locationWatcher.Dispose();
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
