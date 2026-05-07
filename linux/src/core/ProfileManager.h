#pragma once

#include <QObject>
#include <QString>
#include <QList>
#include <QUrl>
#include <QDir>

struct Profile
{
    QString id;
    QString name;
    QString gatewayMac;
    QString wallpaperPath;
    QString thumbnailPath;
    bool isDefault;
    int targetFps = 30;
    bool batteryPause = true;

    bool isVideo() const;
    QStringList supportedFormats() const;
};

class ProfileManager : public QObject
{
    Q_OBJECT

public:
    explicit ProfileManager(QObject *parent = nullptr);
    ~ProfileManager();

    void load();
    void save();

    QList<Profile> profiles() const { return m_profiles; }
    Profile defaultProfile() const;
    Profile profileForMac(const QString &mac) const;

    void addProfile(const Profile &profile);
    void updateProfile(const Profile &profile);
    void removeProfile(const QString &id);

    QString configPath() const { return m_configPath; }

    static QString ilkoDir() { return QDir::homePath() + "/.ilko"; }
    static QString wallpapersDir() { return ilkoDir() + "/wallpapers"; }
    static QString importWallpaper(const QString &sourcePath);
    static void setCurrentWallpaper(const QString &wallpaperPath, const QString &profileId);
    static QString currentWallpaperPath();
    static void writePlayerControl(bool paused, double playbackRate = 1.0, const QString &reason = {});

signals:
    void profilesChanged();
    void activeProfileChanged(const QString &profileId);

private:
    QList<Profile> m_profiles;
    QString m_configPath;
    QString m_activeProfileId;
};

inline bool Profile::isVideo() const
{
    const QString ext = wallpaperPath.mid(wallpaperPath.lastIndexOf('.') + 1).toLower();
    return QStringList{"mp4", "webm", "mov", "avi", "mkv"}.contains(ext);
}

inline QStringList Profile::supportedFormats() const
{
    return QStringList{"mp4", "webm", "mov", "avi", "mkv", "jpg", "jpeg", "png", "bmp", "gif"};
}