#include "GpuDetector.h"

#include <QDir>
#include <QFile>
#include <QTextStream>

static QString envDir()  { return QDir::homePath() + "/.config/plasma-workspace/env"; }
static QString envFile() { return envDir() + "/ilko-decode.sh"; }

QString GpuDetector::envFilePath() { return envFile(); }

bool GpuDetector::isPowerSavingActive()
{
    return QFile::exists(envFile());
}

bool GpuDetector::isHybridNvidiaPlusIgpu()
{
    bool hasNvidia = false;
    bool hasIgpu   = false;

    const QStringList entries =
        QDir("/sys/bus/pci/devices").entryList(QDir::Dirs | QDir::NoDotAndDotDot);

    for (const QString &entry : entries) {
        const QString base = "/sys/bus/pci/devices/" + entry;

        QFile classFile(base + "/class");
        QFile vendorFile(base + "/vendor");
        if (!classFile.open(QIODevice::ReadOnly) || !vendorFile.open(QIODevice::ReadOnly))
            continue;

        const QString pciClass = classFile.readAll().trimmed();
        const QString vendor   = vendorFile.readAll().trimmed();

        // 0x0300xx = VGA compatible controller (display)
        // 0x0302xx = 3D controller (NVIDIA는 하이브리드 노트북에서 보통 이 클래스로 표시)
        if (!pciClass.startsWith("0x0300") && !pciClass.startsWith("0x0302"))
            continue;

        if (vendor == "0x10de")                          hasNvidia = true;
        if (vendor == "0x8086" || vendor == "0x1002")    hasIgpu   = true;
    }

    return hasNvidia && hasIgpu;
}

GpuDetector::ConfigResult GpuDetector::autoConfigureIfNeeded()
{
    if (!isHybridNvidiaPlusIgpu())
        return ConfigResult::NotHybrid;

    if (isPowerSavingActive())
        return ConfigResult::AlreadyActive;

    setEnabled(true);
    return ConfigResult::Applied;
}

void GpuDetector::setEnabled(bool enabled)
{
    if (enabled) {
        QDir().mkpath(envDir());
        QFile f(envFile());
        if (f.open(QIODevice::WriteOnly | QIODevice::Text)) {
            QTextStream s(&f);
            s << "#!/bin/sh\n";
            s << "# ilko: NVIDIA 하드웨어 비디오 디코딩 비활성화 (하이브리드 GPU 절전)\n";
            s << "# ILKO 설정에서 관리됩니다\n";
            s << "export GST_PLUGIN_FEATURE_RANK=nvcodec:NONE\n";
        }
    } else {
        QFile::remove(envFile());
    }
}
