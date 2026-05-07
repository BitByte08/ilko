#include "DisplayManager.h"

#include <QGuiApplication>
#include <QScreen>
#include <QDebug>

#include <KDisplayManager>
#include <KScreen>

DisplayManager::DisplayManager(QObject *parent)
    : QObject(parent)
{
    updateDisplays();

    connect(qApp, &QGuiApplication::screenAdded, this, &DisplayManager::refresh);
    connect(qApp, &QGuiApplication::screenRemoved, this, &DisplayManager::refresh);
}

DisplayManager::~DisplayManager() = default;

void DisplayManager::refresh()
{
    updateDisplays();
    emit displaysChanged();
}

void DisplayManager::updateDisplays()
{
    m_displays.clear();

    const QList<QScreen*> screens = QGuiApplication::screens();

    for (int i = 0; i < screens.size(); ++i) {
        QScreen *screen = screens[i];

        Display display;
        display.id = screen->name();
        display.name = screen->manufacturer() + " " + screen->model();
        display.geometry = screen->geometry();
        display.refreshRate = screen->refreshRate();
        display.scale = screen->devicePixelRatio();
        display.isPrimary = (i == 0);

        m_displays.append(display);
    }
}

DisplayManager::Display DisplayManager::primaryDisplay() const
{
    for (const Display &d : m_displays) {
        if (d.isPrimary) return d;
    }
    return m_displays.isEmpty() ? Display{} : m_displays.first();
}

DisplayManager::Display DisplayManager::displayAt(const QString &id) const
{
    for (const Display &d : m_displays) {
        if (d.id == id) return d;
    }
    return Display{};
}