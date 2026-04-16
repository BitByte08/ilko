#include <QApplication>

#include "ui/MainWindow.h"

int main(int argc, char *argv[])
{
    QApplication app(argc, argv);
    app.setApplicationName("ILKO");
    app.setApplicationVersion("1.0.0");
    app.setDesktopFileName("ilko");

    MainWindow window;
    window.show();

    return app.exec();
}