/*
 * vpn_log.h - native 层统一日志宏
 *
 * 全项目 hilog 约定: domain=0x3200, 三层 tag 分别为
 *   VPNAPP-ETS / VPNAPP-NAPI / VPNAPP-GO
 * 过滤命令: hdc shell "hilog -D 0x3200"
 */
#ifndef VPNAPP_LOG_H
#define VPNAPP_LOG_H

#include <hilog/log.h>

#define VPN_LOG_DOMAIN 0x3200
#define VPN_LOG_TAG "VPNAPP-NAPI"

#define VPN_LOGD(fmt, ...) OH_LOG_Print(LOG_APP, LOG_DEBUG, VPN_LOG_DOMAIN, VPN_LOG_TAG, fmt, ##__VA_ARGS__)
#define VPN_LOGI(fmt, ...) OH_LOG_Print(LOG_APP, LOG_INFO,  VPN_LOG_DOMAIN, VPN_LOG_TAG, fmt, ##__VA_ARGS__)
#define VPN_LOGW(fmt, ...) OH_LOG_Print(LOG_APP, LOG_WARN,  VPN_LOG_DOMAIN, VPN_LOG_TAG, fmt, ##__VA_ARGS__)
#define VPN_LOGE(fmt, ...) OH_LOG_Print(LOG_APP, LOG_ERROR, VPN_LOG_DOMAIN, VPN_LOG_TAG, fmt, ##__VA_ARGS__)
#define VPN_LOGF(fmt, ...) OH_LOG_Print(LOG_APP, LOG_FATAL, VPN_LOG_DOMAIN, VPN_LOG_TAG, fmt, ##__VA_ARGS__)

#endif
