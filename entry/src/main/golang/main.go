// main.go - Go 核心库(libcore.so)入口
//
// 导出符号(供 C++/NAPI 桥接层调用):
//
//	GoInvoke(service, params) *C.char  统一 IPC 入口, service 形如 "Service.Method",
//	                                   params/返回值均为 JSON 字符串, 内部带 panic 捕获
//	GoFreeCString(p)                   释放 GoInvoke 返回的 C 字符串
//	GoUptimeMs()                       库加载至今的毫秒数
//
// 注意: 所有导出函数必须经由桥接层 worker 线程调用(鸿蒙 musl 主线程 TLS 限制)
package main

/*
#include <stdlib.h>
*/
import "C"
import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime/debug"
	"time"
	"unsafe"

	_ "github.com/xtls/xray-core/main/distro/all"

	"vpnapp/core/ipc"
	"vpnapp/core/xlog"

	_ "vpnapp/core/services"
)

var startTime = time.Now()

func main() {}

//export GoInvoke
func GoInvoke(service, parameters *C.char) (result *C.char) {
	start := time.Now()
	svc := C.GoString(service)
	params := C.GoString(parameters)

	defer func() {
		if r := recover(); r != nil {
			stack := string(debug.Stack())
			xlog.Error("ipc", fmt.Sprintf("panic in %s: %v", svc, r), map[string]any{"stack": stack})
			writeCrashFile(svc, r, stack)
			resp := ipc.Fail(&ipc.Error{Code: ipc.ErrPanic, Message: fmt.Sprintf("%v", r), Detail: stack})
			result = C.CString(mustMarshal(resp))
		}
	}()

	resp := ipc.Invoke(svc, json.RawMessage(params))
	elapsed := time.Since(start)
	if resp.Success {
		xlog.Info("ipc", fmt.Sprintf("%s ok in %s", svc, elapsed), nil)
	} else {
		xlog.Warn("ipc", fmt.Sprintf("%s failed in %s: %s %s", svc, elapsed, resp.Error.Code, resp.Error.Message), nil)
	}
	return C.CString(mustMarshal(resp))
}

//export GoFreeCString
func GoFreeCString(result *C.char) {
	C.free(unsafe.Pointer(result))
}

//export GoUptimeMs
func GoUptimeMs() C.longlong {
	return C.longlong(time.Since(startTime).Milliseconds())
}

func mustMarshal(v any) string {
	data, err := json.Marshal(v)
	if err != nil {
		return fmt.Sprintf(`{"success":false,"error":{"code":"INTERNAL","message":"marshal response: %v"}}`, err)
	}
	return string(data)
}

func writeCrashFile(service string, r any, stack string) {
	dir := xlog.LogDir()
	if dir == "" {
		return
	}
	name := fmt.Sprintf("crash_%s.txt", time.Now().Format("20060102_150405"))
	path := filepath.Join(dir, name)
	content := fmt.Sprintf("service: %s\ntime: %s\npanic: %v\n\n%s", service, time.Now().Format(time.RFC3339), r, stack)
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		xlog.Error("ipc", "write crash file failed: "+err.Error(), nil)
	}
}
