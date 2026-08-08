/*
 * bridge.h - NAPI 与 Go 核心库桥接层接口
 *
 * 详见 bridge.cpp 头部注释(线程模型与鸿蒙 TLS 约束说明)
 */
#ifndef VPNAPP_BRIDGE_H
#define VPNAPP_BRIDGE_H

#include <memory>
#include <mutex>
#include <string>

namespace bridge {

struct Status {
    bool loaded;
    std::string libPath;
    std::string lastError;
    long long callCount;
    long long failCount;
    std::string lastService;
    long long lastDurationMs;
};

std::string Invoke(const std::string &service, const std::string &params);
Status GetStatus();
bool Unload();

}

#endif
