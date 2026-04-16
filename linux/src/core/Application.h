#pragma once

#include <QObject>
#include <memory>

class SwitchController;

namespace ilko {

class Application : public QObject
{
    Q_OBJECT

public:
    explicit Application(QObject *parent = nullptr);
    ~Application();

    void initialize();

    SwitchController *switchController() const;

private:
    class Impl;
    std::unique_ptr<Impl> d;
};

}