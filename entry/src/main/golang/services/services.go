// services.go - 框架调试服务
//
//	LogService      Init/SetLevel/GetLevel/Recent/ListFiles/Write
//	StatusService   Get(运行时状态: goroutine/内存/GC)/GC
//	VersionService  Get(框架/Go/xray 版本)
//	PingService     Ping(连通性)/Panic(崩溃管道自检, 仅调试用)
//
// xray 核心服务见 core.go (CoreService)
package services

import (
	"encoding/json"
	"fmt"
	"runtime"
	"time"

	xcore "github.com/xtls/xray-core/core"

	"vpnapp/core/ipc"
	"vpnapp/core/xlog"
)

func parseParams(params json.RawMessage, out any) error {
	if len(params) == 0 || string(params) == "null" {
		return nil
	}
	if err := json.Unmarshal(params, out); err != nil {
		return ipc.WrapError(ipc.ErrBadParams, err)
	}
	return nil
}

type LogService struct{}

type logInitParams struct {
	Dir      string `json:"dir"`
	KeepDays int    `json:"keepDays"`
}

type logSetLevelParams struct {
	Level int `json:"level"`
}

type logRecentParams struct {
	Limit int `json:"limit"`
}

type logWriteParams struct {
	Level  int    `json:"level"`
	Module string `json:"module"`
	Msg    string `json:"msg"`
}

func (s *LogService) Name() string { return "LogService" }

func (s *LogService) Invoke(method string, params json.RawMessage) (any, error) {
	switch method {
	case "Init":
		var p logInitParams
		if err := parseParams(params, &p); err != nil {
			return nil, err
		}
		if p.Dir == "" {
			return nil, ipc.NewError(ipc.ErrBadParams, "dir is required")
		}
		if err := xlog.Init(p.Dir); err != nil {
			return nil, ipc.WrapError(ipc.ErrInternal, err)
		}
		if p.KeepDays <= 0 {
			p.KeepDays = 7
		}
		if err := xlog.CleanOld(p.KeepDays); err != nil {
			xlog.Warn("log", "clean old logs: "+err.Error(), nil)
		}
		xlog.Info("log", "log system initialized", map[string]any{"dir": p.Dir, "keepDays": p.KeepDays})
		return map[string]any{"dir": p.Dir}, nil
	case "SetLevel":
		var p logSetLevelParams
		if err := parseParams(params, &p); err != nil {
			return nil, err
		}
		if p.Level < xlog.LevelDebug || p.Level > xlog.LevelFatal {
			return nil, ipc.NewError(ipc.ErrBadParams, fmt.Sprintf("level must be %d..%d", xlog.LevelDebug, xlog.LevelFatal))
		}
		xlog.SetLevel(p.Level)
		return map[string]int{"level": xlog.GetLevel()}, nil
	case "GetLevel":
		return map[string]int{"level": xlog.GetLevel()}, nil
	case "Recent":
		var p logRecentParams
		if err := parseParams(params, &p); err != nil {
			return nil, err
		}
		return xlog.Recent(p.Limit), nil
	case "ListFiles":
		files, err := xlog.ListFiles()
		if err != nil {
			return nil, ipc.WrapError(ipc.ErrInternal, err)
		}
		return files, nil
	case "Write":
		var p logWriteParams
		if err := parseParams(params, &p); err != nil {
			return nil, err
		}
		if p.Module == "" {
			p.Module = "external"
		}
		xlog.WriteExternal(p.Level, p.Module, p.Msg)
		return map[string]bool{"ok": true}, nil
	default:
		return nil, ipc.NewError(ipc.ErrBadRequest, "unknown method LogService."+method)
	}
}

type StatusService struct {
	start time.Time
}

func (s *StatusService) Name() string { return "StatusService" }

func (s *StatusService) Invoke(method string, params json.RawMessage) (any, error) {
	switch method {
	case "Get":
		var mem runtime.MemStats
		runtime.ReadMemStats(&mem)
		return map[string]any{
			"uptimeMs":      time.Since(s.start).Milliseconds(),
			"goroutines":    runtime.NumGoroutine(),
			"gomaxprocs":    runtime.GOMAXPROCS(0),
			"numCPU":        runtime.NumCPU(),
			"heapAllocMB":   float64(mem.HeapAlloc) / 1024 / 1024,
			"heapSysMB":     float64(mem.HeapSys) / 1024 / 1024,
			"stackInUseMB":  float64(mem.StackInuse) / 1024 / 1024,
			"numGC":         mem.NumGC,
			"lastGCPauseMs": float64(mem.PauseNs[(mem.NumGC+255)%256]) / 1e6,
			"logLevel":      xlog.GetLevel(),
			"logDir":        xlog.LogDir(),
		}, nil
	case "GC":
		runtime.GC()
		return map[string]bool{"ok": true}, nil
	default:
		return nil, ipc.NewError(ipc.ErrBadRequest, "unknown method StatusService."+method)
	}
}

type VersionService struct{}

const frameworkVersion = "1.0.0"

func (s *VersionService) Name() string { return "VersionService" }

func (s *VersionService) Invoke(method string, params json.RawMessage) (any, error) {
	switch method {
	case "Get":
		return map[string]any{
			"framework": frameworkVersion,
			"go":        runtime.Version(),
			"core":      xcore.Version(),
		}, nil
	default:
		return nil, ipc.NewError(ipc.ErrBadRequest, "unknown method VersionService."+method)
	}
}

type PingService struct{}

func (s *PingService) Name() string { return "PingService" }

func (s *PingService) Invoke(method string, params json.RawMessage) (any, error) {
	switch method {
	case "Ping":
		echo := json.RawMessage(params)
		if len(echo) == 0 {
			echo = json.RawMessage("null")
		}
		return map[string]any{
			"echo":      echo,
			"timestamp": time.Now().UnixMilli(),
		}, nil
	default:
		return nil, ipc.NewError(ipc.ErrBadRequest, "unknown method PingService."+method)
	}
}

func init() {
	ipc.Register(&LogService{})
	ipc.Register(&StatusService{start: time.Now()})
	ipc.Register(&VersionService{})
	ipc.Register(&PingService{})
	ipc.Register(&CoreService{})
	xlog.Info("boot", "services registered", map[string]any{"framework": frameworkVersion})
}
