// node.go - 节点工具服务
//
// Ping: 对节点地址做 TCP 连接握手测延迟(毫秒), 失败返回 -1。
// 语义: 代理链路延迟的近似值(VLESS 握手差异很小, TCP 连接延迟足够选节点用)
package services

import (
	"encoding/json"
	"net"
	"strconv"
	"time"

	"vpnapp/core/ipc"
)

type NodeService struct{}

type nodePingParams struct {
	Address   string `json:"address"`
	Port      int    `json:"port"`
	TimeoutMs int    `json:"timeoutMs"`
}

func (s *NodeService) Name() string { return "NodeService" }

func (s *NodeService) Invoke(method string, params json.RawMessage) (any, error) {
	switch method {
	case "Ping":
		var p nodePingParams
		if err := parseParams(params, &p); err != nil {
			return nil, err
		}
		if p.Address == "" || p.Port <= 0 || p.Port > 65535 {
			return nil, ipc.NewError(ipc.ErrBadParams, "invalid address or port")
		}
		if p.TimeoutMs <= 0 {
			p.TimeoutMs = 3000
		}
		return s.ping(p)
	default:
		return nil, ipc.NewError(ipc.ErrBadRequest, "unknown method NodeService."+method)
	}
}

func (s *NodeService) ping(p nodePingParams) (any, error) {
	timeout := time.Duration(p.TimeoutMs) * time.Millisecond
	addr := net.JoinHostPort(p.Address, strconv.Itoa(p.Port))
	start := time.Now()
	conn, err := net.DialTimeout("tcp", addr, timeout)
	latency := int64(-1)
	if err == nil {
		latency = time.Since(start).Milliseconds()
		conn.Close()
	}
	return map[string]any{"latencyMs": latency}, nil
}

func init() {
	ipc.Register(&NodeService{})
}
