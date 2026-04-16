#pragma once

#include <QObject>
#include <QString>
#include <QList>
#include <QUrl>

struct Profile
{
    QString id;
    QString name;
    QString gatewayMac;
    QString wallpaperPath;
    QString thumbnailPath;
    bool isDefault;

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