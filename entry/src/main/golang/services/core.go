// core.go - xray-core 生命周期服务 (CoreService)
//
//	Start(fd, assetLocation, configLocation)  启动核心; fd>0 时写入 xray.tun.fd 环境变量
//	                                          (tun inbound 使用), fd<=0 为纯本地代理模式
//	Stop()                                    停止并释放(GC + FreeOSMemory)
//	State()                                   running/version/uptime
//
// xray 的 console 日志经 xrayLogHandler 桥接进 xlog 统一日志流
package services

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"runtime"
	"runtime/debug"
	"sync"
	"time"

	appLog "github.com/xtls/xray-core/app/log"
	commonLog "github.com/xtls/xray-core/common/log"
	"github.com/xtls/xray-core/common/platform"
	xcore "github.com/xtls/xray-core/core"
	xstats "github.com/xtls/xray-core/features/stats"

	"vpnapp/core/ipc"
	"vpnapp/core/xlog"
)

type CoreService struct {
	mu        sync.Mutex
	instance  *xcore.Instance
	startedAt time.Time
	logOnce   sync.Once
}

type coreStartParams struct {
	Fd             int    `json:"fd"`
	AssetLocation  string `json:"assetLocation"`
	ConfigLocation string `json:"configLocation"`
}

type xrayLogHandler struct{}

func (h *xrayLogHandler) Handle(msg commonLog.Message) {
	sev := "?"
	switch msg.(type) {
	case *commonLog.GeneralMessage:
		sev = msg.(*commonLog.GeneralMessage).Severity.String()
	}
	switch sev {
	case "Debug":
		xlog.Debug("xray", msg.String(), nil)
	case "Info":
		xlog.Info("xray", msg.String(), nil)
	case "Warning":
		xlog.Warn("xray", msg.String(), nil)
	case "Error":
		xlog.Error("xray", msg.String(), nil)
	default:
		xlog.Info("xray", msg.String(), nil)
	}
}

func (s *CoreService) hookXrayLog() {
	s.logOnce.Do(func() {
		appLog.RegisterHandlerCreator(appLog.LogType_Console, func(_ appLog.LogType, _ appLog.HandlerCreatorOptions) (commonLog.Handler, error) {
			return &xrayLogHandler{}, nil
		})
		xlog.Info("core", "xray console log bridged to xlog", nil)
	})
}

func (s *CoreService) Name() string { return "CoreService" }

func (s *CoreService) Invoke(method string, params json.RawMessage) (any, error) {
	switch method {
	case "Start":
		var p coreStartParams
		if err := parseParams(params, &p); err != nil {
			return nil, err
		}
		return s.start(&p)
	case "Stop":
		return s.stop()
	case "State":
		return s.state()
	case "Stats":
		return s.stats()
	default:
		return nil, ipc.NewError(ipc.ErrBadRequest, "unknown method CoreService."+method)
	}
}

/*
 * Stats 读取 xray 内核统计计数器(需在 config policy 中开启 statsOutbound*),
 * 返回各出站 tag 的累计收发字节: {"proxy":{"up":n,"down":n},"direct":{...},...}
 */
func (s *CoreService) stats() (any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.instance == nil || !s.instance.IsRunning() {
		return nil, ipc.NewError(ipc.ErrNotReady, "core not running")
	}
	mgr, ok := s.instance.GetFeature(xstats.ManagerType()).(xstats.Manager)
	if !ok || mgr == nil {
		return nil, ipc.NewError(ipc.ErrInternal, "stats manager unavailable")
	}
	out := map[string]map[string]int64{}
	for _, tag := range []string{"proxy", "direct", "block", "dns-out"} {
		up := mgr.GetCounter("outbound>>>" + tag + ">>>traffic>>>uplink")
		down := mgr.GetCounter("outbound>>>" + tag + ">>>traffic>>>downlink")
		entry := map[string]int64{}
		if up != nil {
			entry["up"] = up.Value()
		}
		if down != nil {
			entry["down"] = down.Value()
		}
		if len(entry) > 0 {
			out[tag] = entry
		}
	}
	return out, nil
}

func (s *CoreService) start(p *coreStartParams) (any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if p.ConfigLocation == "" {
		return nil, ipc.NewError(ipc.ErrBadParams, "configLocation is required")
	}

	if s.instance != nil {
		if s.instance.IsRunning() {
			if err := s.instance.Close(); err != nil {
				xlog.Warn("core", "close previous instance: "+err.Error(), nil)
			}
		}
		s.instance = nil
		runtime.GC()
	}

	if p.AssetLocation != "" {
		os.Setenv(platform.AssetLocation, p.AssetLocation)
	}
	if p.Fd > 0 {
		os.Setenv(platform.TunFdKey, fmt.Sprintf("%d", p.Fd))
	} else {
		os.Unsetenv(platform.TunFdKey)
	}

	data, err := os.ReadFile(p.ConfigLocation)
	if err != nil {
		return nil, ipc.WrapError(ipc.ErrBadParams, fmt.Errorf("read config: %w", err))
	}
	config, err := xcore.LoadConfig("json", bytes.NewReader(data))
	if err != nil {
		return nil, ipc.WrapError(ipc.ErrBadParams, fmt.Errorf("parse config: %w", err))
	}

	s.hookXrayLog()

	inst, err := xcore.New(config)
	if err != nil {
		return nil, ipc.WrapError(ipc.ErrInternal, fmt.Errorf("core.New: %w", err))
	}
	if err := inst.Start(); err != nil {
		_ = inst.Close()
		return nil, ipc.WrapError(ipc.ErrInternal, fmt.Errorf("core.Start: %w", err))
	}
	s.instance = inst
	s.startedAt = time.Now()
	runtime.GC()
	debug.FreeOSMemory()

	xlog.Info("core", "xray started", map[string]any{
		"version": xcore.Version(),
		"config":  p.ConfigLocation,
		"fd":      p.Fd,
	})
	return map[string]any{
		"running": true,
		"version": xcore.Version(),
	}, nil
}

func (s *CoreService) stop() (any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.instance == nil {
		return map[string]any{"running": false, "was": false}, nil
	}
	if s.instance.IsRunning() {
		if err := s.instance.Close(); err != nil {
			return nil, ipc.WrapError(ipc.ErrInternal, err)
		}
	}
	s.instance = nil
	runtime.GC()
	debug.FreeOSMemory()
	xlog.Info("core", "xray stopped", nil)
	return map[string]any{"running": false, "was": true}, nil
}

func (s *CoreService) state() (any, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	running := s.instance != nil && s.instance.IsRunning()
	out := map[string]any{
		"running": running,
		"version": xcore.Version(),
	}
	if running {
		out["uptimeMs"] = time.Since(s.startedAt).Milliseconds()
	}
	return out, nil
}
