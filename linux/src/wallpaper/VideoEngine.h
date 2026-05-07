#pragma once

#include <QObject>
#include <QString>
#include <QRect>
#include <QList>
#include <memory>

class QWindow;
class QVideoSink;

namespace ilko {

class VideoEngine : public QObject
{
    Q_OBJECT

public:
    explicit VideoEngine(QObject *parent = nullptr);
    ~VideoEngine();

    void play(const QString &videoPath);
    void playOnDisplay(const QString &videoPath, const QString &displayId);
    void stop();
    void stopDisplay(const QString &displayId);

    bool isPlaying() const { return m_playing; }
    QString currentVideo() const { return m_currentVideo; }

    void setVolume(qreal volume);
    qreal volume() const { return m_volume; }

    void setMuted(bool muted);
    bool isMuted() const { return m_muted; }

    void setFitMode(int mode);
    int fitMode() const { return m_fitMode; }

    enum FitMode {
        FitModeFill = 0,
        FitModeFit = 1,
        FitModeStretch = 2,
        FitModeCenter = 3,
        FitModeScale = 4
    };
    Q_ENUM(FitMode)

signals:
    void playbackStateChanged(bool playing);
    void error(const QString &message);

private:
    void updateWindows();

    struct DisplayWindow
    {
        QString displayId;
        QWindow *window;
        void *mediaPlayer;
    };

    QList<DisplayWindow> m_windows;
    QString m_currentVideo;
    bool m_playing;
    qreal m_volume;
    bool m_muted;
    int m_fitMode;
};

}