#pragma once

#include <QObject>
#include <memory>

namespace ilko {

class Application : public QObject
{
    Q_OBJECT

public:
    explicit Application(QObject *parent = nullptr);
    ~Application();

    void initialize();

private:
    class Impl;
    std::unique_ptr<Impl> d;
};

}