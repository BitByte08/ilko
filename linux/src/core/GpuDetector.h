#pragma once

#include <QString>

class GpuDetector {
public:
    enum class ConfigResult {
        NotHybrid,     // 단일 GPU — 조치 없음
        AlreadyActive, // 이미 env 파일 존재
        Applied,       // 하이브리드 감지 → env 파일 새로 생성
    };

    // /sys/bus/pci/devices 스캔으로 하이브리드 구성 판별 (subprocess 없음)
    static bool isHybridNvidiaPlusIgpu();

    static bool isPowerSavingActive();

    // 하이브리드 감지 시 env 파일 자동 생성. 이미 존재하면 AlreadyActive 반환.
    static ConfigResult autoConfigureIfNeeded();

    // 수동 오버라이드 (Settings에서 체크박스)
    static void setEnabled(bool enabled);

    static QString envFilePath();
};
