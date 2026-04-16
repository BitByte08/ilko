#include "ProfileManager.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QFile>
#include <QDir>
#include <QStandardPaths>
#include <QUuid>

ProfileManager::ProfileManager(QObject *parent)
    : QObject(parent)
    , m_configPath(QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation) + "/profiles.json")
{
}

ProfileManager::~ProfileManager() = default;

void ProfileManager::load()
{
    m_profiles.clear();

    if (!QFile::exists(m_configPath)) {
        Profile defaultProfile;
        defaultProfile.id = QUuid::createUuid().toString();
        defaultProfile.name = QStringLiteral("기본 (일코)");
        defaultProfile.gatewayMac.clear();
        defaultProfile.wallpaperPath.clear();
        defaultProfile.thumbnailPath.clear();
        defaultProfile.isDefault = true;
        m_profiles.append(defaultProfile);
        
        QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation));
        save();
        return;
    }

    QFile file(m_configPath);
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }

    QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
    file.close();

    if (!doc.isObject()) {
        return;
    }

    QJsonObject obj = doc.object();
    m_activeProfileId = obj.value("activeProfile").toString();

    QJsonArray profilesArray = obj.value("profiles").toArray();
    for (const auto &item : profilesArray) {
        if (!item.isObject()) continue;

        QJsonObject p = item.toObject();
        Profile profile;
        profile.id = p.value("id").toString();
        profile.name = p.value("name").toString();
        profile.gatewayMac = p.value("gatewayMac").toString();
        profile.wallpaperPath = p.value("wallpaperPath").toString();
        profile.thumbnailPath = p.value("thumbnailPath").toString();
        profile.isDefault = p.value("isDefault").toBool(false);
        m_profiles.append(profile);
    }
}

void ProfileManager::save()
{
    QJsonObject obj;
    obj.insert("activeProfile", m_activeProfileId);

    QJsonArray profilesArray;
    for (const Profile &p : m_profiles) {
        QJsonObject profile;
        profile.insert("id", p.id);
        profile.insert("name", p.name);
        profile.insert("gatewayMac", p.gatewayMac);
        profile.insert("wallpaperPath", p.wallpaperPath);
        profile.insert("thumbnailPath", p.thumbnailPath);
        profile.insert("isDefault", p.isDefault);
        profilesArray.append(profile);
    }
    obj.insert("profiles", profilesArray);

    QDir().mkpath(QStandardPaths::writableLocation(QStandardPaths::AppConfigLocation));
    
    QFile file(m_configPath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
        file.close();
    }
}

Profile ProfileManager::defaultProfile() const
{
    for (const Profile &p : m_profiles) {
        if (p.isDefault) return p;
    }
    return Profile{};
}

Profile ProfileManager::profileForMac(const QString &mac) const
{
    for (const Profile &p : m_profiles) {
        if (!p.isDefault && p.gatewayMac.toLower() == mac.toLower()) {
            return p;
        }
    }
    return defaultProfile();
}

void ProfileManager::addProfile(const Profile &profile)
{
    m_profiles.append(profile);
    save();
    emit profilesChanged();
}

void ProfileManager::updateProfile(const Profile &profile)
{
    for (int i = 0; i < m_profiles.size(); ++i) {
        if (m_profiles[i].id == profile.id) {
            m_profiles[i] = profile;
            break;
        }
    }
    save();
    emit profilesChanged();
}

void ProfileManager::removeProfile(const QString &id)
{
    QList<Profile> newList;
    for (const Profile &p : m_profiles) {
        if (p.id != id) {
            newList.append(p);
        }
    }
    m_profiles = newList;
    save();
    emit profilesChanged();
}