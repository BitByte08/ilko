#pragma once

#include <QObject>
#include <QList>
#include <QRect>
#include <QString>

namespace ilko {

class DisplayManager : public QObject
{
    Q_OBJECT

public:
    explicit DisplayManager(QObject *parent = nullptr);
    ~DisplayManager();

    struct Display
    {
        QString id;
        QString name;
        QRect geometry;
        int refreshRate;
        qreal scale;
        bool isPrimary;
    };

    QList<Display> displays() const { return m_displays; }
    Display primaryDisplay() const;
    Display displayAt(const QString &id) const;
    int displayCount() const { return m_displays.size(); }

    void refresh();

signals:
    void displaysChanged();

private:
    void updateDisplays();

    QList<Display> m_displays;
};

}