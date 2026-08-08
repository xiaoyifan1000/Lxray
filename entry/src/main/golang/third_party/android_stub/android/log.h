#ifndef ANDROID_LOG_H
#define ANDROID_LOG_H

#include <stdarg.h>
#include <hilog/log.h>

#define ANDROID_LOG_UNKNOWN 0
#define ANDROID_LOG_DEFAULT 1
#define ANDROID_LOG_VERBOSE 2
#define ANDROID_LOG_DEBUG   3
#define ANDROID_LOG_INFO    4
#define ANDROID_LOG_WARN    5
#define ANDROID_LOG_ERROR   6
#define ANDROID_LOG_FATAL   7
#define ANDROID_LOG_SILENT  8

static inline int __android_log_vprint(int prio, const char *tag, const char *fmt, va_list ap) {
    if (prio < LOG_DEBUG) {
        prio = LOG_DEBUG;
    }
    if (prio > LOG_FATAL) {
        prio = LOG_FATAL;
    }
    return OH_LOG_VPrint(LOG_APP, (LogLevel)prio, 0x3200, tag, fmt, ap);
}

static inline int __android_log_print(int prio, const char *tag, const char *fmt, ...) {
    int r;
    va_list ap;
    va_start(ap, fmt);
    r = __android_log_vprint(prio, tag, fmt, ap);
    va_end(ap);
    return r;
}

static inline void __android_log_write(int prio, const char *tag, const char *msg) {
    __android_log_print(prio, tag, "%{public}s", msg);
}

#endif
