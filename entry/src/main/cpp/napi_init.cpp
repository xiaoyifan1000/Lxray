/*
 * napi_init.cpp - NAPI 模块入口, 向 ArkTS 暴露桥接接口
 *
 * 导出函数(libentry.so):
 *   invoke(service, params[, callback]) -> Promise<string>  异步调用(ffrt 线程池执行)
 *   invokeSync(service, params) -> string                   同步调用(内部仍经 worker 线程)
 *   getBridgeStatus() -> BridgeStatus                       桥状态(加载/计数/错误)
 *   selfTest() -> string                                    连通性自检(PingService.Ping)
 *
 * 安全说明: 所有 Go 调用最终都进入 bridge 的 worker 线程, 与调用线程无关,
 * 因此同步/异步接口在鸿蒙主线程 TLS 限制下都是安全的
 */
#include "napi/native_api.h"
#include "bridge.h"
#include "vpn_log.h"

#include <string>

namespace {

struct InvokeContext {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    napi_ref callback = nullptr;
    bool isPromise = true;
    std::string service;
    std::string params;
    std::string result;
};

bool GetStringArg(napi_env env, napi_value arg, std::string &out) {
    size_t len = 0;
    if (napi_get_value_string_utf8(env, arg, nullptr, 0, &len) != napi_ok) {
        return false;
    }
    out.resize(len + 1);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, arg, &out[0], len + 1, &copied) != napi_ok) {
        return false;
    }
    out.resize(copied);
    return true;
}

void InvokeExecute(napi_env env, void *data) {
    auto *ctx = static_cast<InvokeContext *>(data);
    ctx->result = bridge::Invoke(ctx->service, ctx->params);
}

void InvokeComplete(napi_env env, napi_status status, void *data) {
    auto *ctx = static_cast<InvokeContext *>(data);
    napi_value result;
    napi_create_string_utf8(env, ctx->result.c_str(), ctx->result.size(), &result);
    if (ctx->isPromise) {
        napi_resolve_deferred(env, ctx->deferred, result);
    } else {
        napi_value undefined;
        napi_get_undefined(env, &undefined);
        napi_value callback;
        napi_get_reference_value(env, ctx->callback, &callback);
        napi_value argv[1] = {result};
        napi_call_function(env, undefined, callback, 1, argv, nullptr);
        napi_delete_reference(env, ctx->callback);
    }
    napi_delete_async_work(env, ctx->work);
    delete ctx;
}

napi_value Invoke(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_error(env, "BAD_PARAMS", "invoke(service, params[, callback]) requires 2 arguments");
        return nullptr;
    }
    auto *ctx = new InvokeContext();
    if (!GetStringArg(env, args[0], ctx->service) || !GetStringArg(env, args[1], ctx->params)) {
        delete ctx;
        napi_throw_error(env, "BAD_PARAMS", "service and params must be strings");
        return nullptr;
    }

    napi_value resourceName;
    napi_create_string_utf8(env, "VpnBridgeInvoke", NAPI_AUTO_LENGTH, &resourceName);

    napi_value promiseOrUndefined = nullptr;
    napi_valuetype cbType = napi_undefined;
    if (argc >= 3) {
        napi_typeof(env, args[2], &cbType);
    }
    if (cbType == napi_function) {
        ctx->isPromise = false;
        napi_create_reference(env, args[2], 1, &ctx->callback);
        napi_get_undefined(env, &promiseOrUndefined);
    } else {
        ctx->isPromise = true;
        napi_create_promise(env, &ctx->deferred, &promiseOrUndefined);
    }
    napi_create_async_work(env, nullptr, resourceName, InvokeExecute, InvokeComplete, ctx, &ctx->work);
    napi_queue_async_work(env, ctx->work);
    return promiseOrUndefined;
}

napi_value InvokeSync(napi_env env, napi_callback_info info) {
    size_t argc = 2;
    napi_value args[2] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_error(env, "BAD_PARAMS", "invokeSync(service, params) requires 2 arguments");
        return nullptr;
    }
    std::string service, params;
    if (!GetStringArg(env, args[0], service) || !GetStringArg(env, args[1], params)) {
        napi_throw_error(env, "BAD_PARAMS", "service and params must be strings");
        return nullptr;
    }
    std::string result = bridge::Invoke(service, params);
    napi_value out;
    napi_create_string_utf8(env, result.c_str(), result.size(), &out);
    return out;
}

napi_value GetBridgeStatus(napi_env env, napi_callback_info info) {
    bridge::Status st = bridge::GetStatus();
    napi_value obj;
    napi_create_object(env, &obj);
    napi_value v;
    napi_get_boolean(env, st.loaded, &v);
    napi_set_named_property(env, obj, "loaded", v);
    napi_create_string_utf8(env, st.libPath.c_str(), NAPI_AUTO_LENGTH, &v);
    napi_set_named_property(env, obj, "libPath", v);
    napi_create_string_utf8(env, st.lastError.c_str(), NAPI_AUTO_LENGTH, &v);
    napi_set_named_property(env, obj, "lastError", v);
    napi_create_int64(env, st.callCount, &v);
    napi_set_named_property(env, obj, "callCount", v);
    napi_create_int64(env, st.failCount, &v);
    napi_set_named_property(env, obj, "failCount", v);
    napi_create_string_utf8(env, st.lastService.c_str(), NAPI_AUTO_LENGTH, &v);
    napi_set_named_property(env, obj, "lastService", v);
    napi_create_int64(env, st.lastDurationMs, &v);
    napi_set_named_property(env, obj, "lastDurationMs", v);
    return obj;
}

napi_value SelfTest(napi_env env, napi_callback_info info) {
    std::string result = bridge::Invoke("PingService.Ping", "{\"source\":\"selfTest\"}");
    napi_value out;
    napi_create_string_utf8(env, result.c_str(), result.size(), &out);
    return out;
}

EXTERN_C_START
napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"invoke", nullptr, Invoke, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"invokeSync", nullptr, InvokeSync, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"getBridgeStatus", nullptr, GetBridgeStatus, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"selfTest", nullptr, SelfTest, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    VPN_LOGI("vpn bridge napi module registered");
    return exports;
}
EXTERN_C_END

napi_module vpnBridgeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule(void) {
    napi_module_register(&vpnBridgeModule);
}

}
