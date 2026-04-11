using System.IO;
using System.Text.Json;
using Ilko.Models;

namespace Ilko.Services;

/// <summary>
/// 프로필 CRUD + %APPDATA%\ilko\config.json 영속성.
/// macOS 버전의 ProfileManager.swift 와 동일 기능.
/// </summary>
public class ProfileManager
{
    private readonly string _configPath;
    private readonly string _wallpapersDir;

    public List<Profile> Profiles { get; private set; } = [];

    public string? ActiveProfileId { get; set; }

    public string WallpapersDirectory => _wallpapersDir;

    public event Action? ProfilesChanged;

    public ProfileManager()
    {
        var appData = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ilko");
        Directory.CreateDirectory(appData);

        _wallpapersDir = Path.Combine(appData, "Wallpapers");
        Directory.CreateDirectory(_wallpapersDir);

        _configPath = Path.Combine(appData, "config.json");
        Load();

        if (Profiles.Count == 0)
        {
            Profiles.Add(new Profile { Name = "기본 (일코)", GatewayMAC = null, WallpaperPath = "" });
            Save();
        }
    }

    public void Add(Profile profile)
    {
        Profiles.Add(profile);
        Save();
    }

    public void Update(Profile profile)
    {
        var idx = Profiles.FindIndex(p => p.Id == profile.Id);
        if (idx < 0) return;
        Profiles[idx] = profile;
        Save();
    }

    public void Delete(string id)
    {
        Profiles.RemoveAll(p => p.Id == id);
        if (ActiveProfileId == id) ActiveProfileId = null;
        Save();
    }

    /// <summary>
    /// 게이트웨이 MAC에 맞는 프로필 반환. 없으면 기본 프로필(GatewayMAC == null).
    /// </summary>
    public Profile? ProfileFor(string? gatewayMAC)
    {
        if (gatewayMAC != null)
        {
            var match = Profiles.FirstOrDefault(p =>
                string.Equals(p.GatewayMAC, gatewayMAC, StringComparison.OrdinalIgnoreCase));
            if (match != null) return match;
        }
        return Profiles.FirstOrDefault(p => p.GatewayMAC == null);
    }

    /// <summary>
    /// 파일을 ilko 월페이퍼 디렉터리로 복사. 이미 같은 경로면 그대로 반환.
    /// </summary>
    public string ImportWallpaper(string sourcePath)
    {
        var dest = Path.Combine(_wallpapersDir, Path.GetFileName(sourcePath));
        if (string.Equals(dest, sourcePath, StringComparison.OrdinalIgnoreCase))
            return dest;
        File.Copy(sourcePath, dest, overwrite: true);
        return dest;
    }

    public void Save()
    {
        var json = JsonSerializer.Serialize(Profiles, new JsonSerializerOptions { WriteIndented = true });
        File.WriteAllText(_configPath, json);
        ProfilesChanged?.Invoke();
    }

    private void Load()
    {
        if (!File.Exists(_configPath)) return;
        try
        {
            var json = File.ReadAllText(_configPath);
            Profiles = JsonSerializer.Deserialize<List<Profile>>(json) ?? [];
        }
        catch
        {
            Profiles = [];
        }
    }
}
