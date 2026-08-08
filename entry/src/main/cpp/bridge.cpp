/*
 * bridge.cpp - ArkTS(NAPI) 与 Go c-shared 库(libcore.so) 之间的桥接层
 *
 * 职责:
 *   1. 延迟加载 libcore.so (dlopen), 解析 GoInvoke/GoFreeCString 符号
 *   2. 所有 Go 导出函数调用均在专用 worker 线程上执行
 *      [关键] 鸿蒙 musl 主线程 TLS 布局与 pthread_create 线程不同,
 *      Go runtime 的 inittls 探测的 TLS 偏移只对标准 pthread 线程有效;
 *      在主线程直接进入 Go 会读到错误的 g 导致 SIGSEGV, 因此必须经 worker 线程
 *   3. 调用串行化: Go 侧服务注册表非并发安全, 单 worker 天然保证串行
 *   4. 启动时将 stderr 重定向到文件, 捕获 Go runtime 的致命错误输出
 *
 * 线程模型:
 *   调用方(napi main/ffrt) -> 队列 -> 单个 worker pthread -> GoInvoke
 *   调用方阻塞等待结果(condvar), 异步语义由 napi async work 提供
 */
#include "bridge.h"
#include "vpn_log.h"

#include <dlfcn.h>
#include <pthread.h>
#include <chrono>
#include <condition_variable>
#include <deque>
#include <fcntl.h>
#include <unistd.h>

namespace bridge {

typedef char *(*GoInvokeFn)(const char *, const char *);
typedef void (*GoFreeCStringFn)(char *);

static void *gHandle = nullptr;
static GoInvokeFn gGoInvoke = nullptr;
static GoFreeCStringFn gGoFree = nullptr;
static std::mutex gMutex;
static Status gStatus = {false, "libcore.so", "", 0, 0, "", 0};
static bool gStderrRedirected = false;

struct Job {
    std::string service;
    std::string params;
    std::string result;
    bool done = false;
    std::condition_variable cv;
};

static std::mutex gQueueMutex;
static std::condition_variable gQueueCv;
static std::deque<std::shared_ptr<Job>> gQueue;
static pthread_t gWorker;
static bool gWorkerStarted = false;

static void redirectStderrOnce() {
    if (gStderrRedirected) {
        return;
    }
    gStderrRedirected = true;
    const char *path = "/data/storage/el2/base/haps/entry/files/go_stderr.log";
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) {
        VPN_LOGW("stderr redirect open failed: %{public}d", errno);
        return;
    }
    if (dup2(fd, STDERR_FILENO) < 0) {
        VPN_LOGW("stderr redirect dup2 failed: %{public}d", errno);
        close(fd);
        return;
    }
    close(fd);
    VPN_LOGI("stderr redirected to go_stderr.log");
}

static bool ensureLoaded() {
    if (gHandle != nullptr && gGoInvoke != nullptr) {
        return true;
    }
    redirectStderrOnce();
    dlerror();
    void *h = dlopen("libcore.so", RTLD_NOW | RTLD_GLOBAL);
    if (h == nullptr) {
        const char *err = dlerror();
        gStatus.lastError = err != nullptr ? err : "unknown dlopen error";
        gStatus.loaded = false;
        VPN_LOGE("dlopen libcore.so failed: %{public}s", gStatus.lastError.c_str());
        return false;
    }
    auto invoke = reinterpret_cast<GoInvokeFn>(dlsym(h, "GoInvoke"));
    auto freeFn = reinterpret_cast<GoFreeCStringFn>(dlsym(h, "GoFreeCString"));
    if (invoke == nullptr || freeFn == nullptr) {
        const char *err = dlerror();
        gStatus.lastError = std::string("dlsym failed: ") + (err != nullptr ? err : "symbol not found");
        gStatus.loaded = false;
        dlclose(h);
        VPN_LOGE("%{public}s", gStatus.lastError.c_str());
        return false;
    }
    gHandle = h;
    gGoInvoke = invoke;
    gGoFree = freeFn;
    gStatus.loaded = true;
    gStatus.lastError = "";
    VPN_LOGI("libcore.so loaded");
    return true;
}

static void *workerMain(void *) {
    VPN_LOGI("bridge worker thread started");
    while (true) {
        std::shared_ptr<Job> job;
        {
            std::unique_lock<std::mutex> lock(gQueueMutex);
            gQueueCv.wait(lock, [] { return !gQueue.empty(); });
            job = gQueue.front();
            gQueue.pop_front();
        }
        char *raw = gGoInvoke(job->service.c_str(), job->params.c_str());
        if (raw != nullptr) {
            job->result = raw;
            gGoFree(raw);
        }
        {
            std::lock_guard<std::mutex> lock(gQueueMutex);
            job->done = true;
        }
        job->cv.notify_all();
    }
    return nullptr;
}

static bool ensureWorker() {
    std::lock_guard<std::mutex> lock(gMutex);
    if (gWorkerStarted) {
        return true;
    }
    if (pthread_create(&gWorker, nullptr, workerMain, nullptr) != 0) {
        gStatus.lastError = "pthread_create failed";
        VPN_LOGE("bridge worker pthread_create failed");
        return false;
    }
    pthread_detach(gWorker);
    gWorkerStarted = true;
    return true;
}

static std::string failJson(const char *code, const std::string &message) {
    std::string escaped;
    escaped.reserve(message.size() + 8);
    for (char c : message) {
        switch (c) {
            case '"': escaped += "\\\""; break;
            case '\\': escaped += "\\\\"; break;
            case '\n': escaped += "\\n"; break;
            case '\r': escaped += "\\r"; break;
            case '\t': escaped += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) {
                    char tmp[8];
                    snprintf(tmp, sizeof(tmp), "\\u%04x", c);
                    escaped += tmp;
                } else {
                    escaped += c;
                }
        }
    }
    return std::string("{\"success\":false,\"error\":{\"code\":\"") + code + "\",\"message\":\"" + escaped + "\"}}";
}

std::string Invoke(const std::string &service, const std::string &params) {
    auto start = std::chrono::steady_clock::now();

    {
        std::lock_guard<std::mutex> lock(gMutex);
        if (!ensureLoaded()) {
            gStatus.failCount++;
            return failJson("LIB_NOT_LOADED", gStatus.lastError);
        }
    }
    if (!ensureWorker()) {
        std::lock_guard<std::mutex> lock(gMutex);
        gStatus.failCount++;
        return failJson("WORKER_FAILED", gStatus.lastError);
    }

    auto job = std::make_shared<Job>();
    job->service = service;
    job->params = params;
    {
        std::lock_guard<std::mutex> lock(gQueueMutex);
        gQueue.push_back(job);
    }
    gQueueCv.notify_one();

    {
        std::unique_lock<std::mutex> lock(gQueueMutex);
        job->cv.wait(lock, [&job] { return job->done; });
    }

    if (job->result.empty()) {
        std::lock_guard<std::mutex> lock(gMutex);
        gStatus.failCount++;
        gStatus.lastError = "GoInvoke returned null";
        VPN_LOGE("GoInvoke(%{public}s) returned null", service.c_str());
        return failJson("NATIVE_NULL_RESULT", gStatus.lastError);
    }

    auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now() - start).count();
    {
        std::lock_guard<std::mutex> lock(gMutex);
        gStatus.callCount++;
        gStatus.lastService = service;
        gStatus.lastDurationMs = elapsed;
        if (job->result.find("\"success\":false") != std::string::npos) {
            gStatus.failCount++;
        }
    }
    return job->result;
}

Status GetStatus() {
    std::lock_guard<std::mutex> lock(gMutex);
    return gStatus;
}

bool Unload() {
    std::lock_guard<std::mutex> lock(gMutex);
    if (gHandle == nullptr) {
        return true;
    }
    gGoInvoke = nullptr;
    gGoFree = nullptr;
    gHandle = nullptr;
    gStatus.loaded = false;
    VPN_LOGW("libcore.so detached from bridge (dlclose skipped: Go runtime cannot be safely unloaded)");
    return true;
}

}
