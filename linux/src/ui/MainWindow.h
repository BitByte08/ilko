#pragma once

#include <QMainWindow>
#include <QSystemTrayIcon>
#include <QMenu>
#include <QListWidget>
#include <QLineEdit>
#include <QPushButton>
#include <QLabel>
#include <QVBoxLayout>
#include <QToolBar>
#include <QDialog>
#include <QComboBox>
#include <QSlider>
#include <QFileDialog>
#include <QMessageBox>
#include <QPixmap>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QFile>
#include <QDir>
#include <QUuid>
#include <QProcess>

struct ProfileData {
    QString id, name, gatewayMac, wallpaperPath;
    bool isDefault;
    static QList<ProfileData> loadAll();
    static void saveAll(const QList<ProfileData>& profiles);
    static void ensureDefaultExists();
};

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget *p = nullptr);
    ~MainWindow();
private slots:
    void onTrayIconActivated(QSystemTrayIcon::ActivationReason);
    void onQuit();
    void showSettingsDialog();
    void showProfilesDialog();
    void updateVideoGrid();
    void onVideoDoubleClicked(QListWidgetItem*);
private:
    void setupUi();
    void setupTrayIcon();
    QSystemTrayIcon *m_trayIcon = nullptr;
    QMenu *m_trayMenu = nullptr;
    QListWidget *m_videoGrid = nullptr;
};

class ProfilesDialog : public QDialog {
    Q_OBJECT
public:
    explicit ProfilesDialog(QWidget *p = nullptr);
private slots:
    void addProfile();
    void editSelectedProfile();
    void deleteSelectedProfile();
private:
    void refreshList();
    QListWidget *m_list = nullptr;
    QList<ProfileData> m_profiles;
};

class ProfileEditDialog : public QDialog {
    Q_OBJECT
public:
    explicit ProfileEditDialog(const ProfileData&, bool isNew, QWidget *p = nullptr);
    ProfileData getProfile() const;
private slots:
    void selectWallpaper();
    void save();
private:
    ProfileData m_profile;
    bool m_isNew;
    QLineEdit *m_nameEdit = nullptr, *m_macEdit = nullptr, *m_wallpaperEdit = nullptr;
    QLabel *m_previewLabel = nullptr;
    QPushButton *m_saveBtn = nullptr;
};

class SettingsDialog : public QDialog {
    Q_OBJECT
public:
    explicit SettingsDialog(QWidget *p = nullptr);
private slots:
    void selectFolder();
    void clearCache();
private:
    QLineEdit *m_folderEdit = nullptr;
    QSlider *m_volumeSlider = nullptr;
    QComboBox *m_scaleCombo = nullptr;
};