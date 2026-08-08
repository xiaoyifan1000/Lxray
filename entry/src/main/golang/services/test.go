// test.go - 出口检测服务
//
// CheckIp: 经本地 xray socks(127.0.0.1:10808) 请求 ipinfo.io,
// 返回代理节点的真实出口 IP 与地理位置(用于验证节点出口)
package services

import (
	"encoding/json"
	"io"
	"net/http"
	"time"

	"golang.org/x/net/proxy"

	"vpnapp/core/ipc"
)

type TestService struct{}

type ipInfo struct {
	IP      string `json:"ip"`
	City    string `json:"city"`
	Region  string `json:"region"`
	Country string `json:"country"`
}

func (s *TestService) Name() string { return "TestService" }

func (s *TestService) Invoke(method string, params json.RawMessage) (any, error) {
	switch method {
	case "CheckIp":
		return s.checkIp()
	default:
		return nil, ipc.NewError(ipc.ErrBadRequest, "unknown method TestService."+method)
	}
}

func (s *TestService) checkIp() (any, error) {
	dialer, err := proxy.SOCKS5("tcp", "127.0.0.1:10808", nil, proxy.Direct)
	if err != nil {
		return nil, ipc.WrapError(ipc.ErrInternal, err)
	}
	ctxDialer, ok := dialer.(proxy.ContextDialer)
	if !ok {
		return nil, ipc.NewError(ipc.ErrInternal, "dialer does not support context dialing")
	}
	client := &http.Client{
		Transport: &http.Transport{DialContext: ctxDialer.DialContext},
		Timeout:   15 * time.Second,
	}

	// ip-api.com 主用(免费, 含地区), 限流时回退 ipify
	for _, endpoint := range []string{"http://ip-api.com/json/", "https://api.ipify.org?format=json"} {
		resp, err := client.Get(endpoint)
		if err != nil {
			continue
		}
		body, readErr := io.ReadAll(resp.Body)
		resp.Body.Close()
		if readErr != nil || resp.StatusCode != http.StatusOK {
			continue
		}
		var info ipInfo
		if json.Unmarshal(body, &info) != nil {
			continue
		}
		if info.IP == "" {
			continue
		}
		return map[string]any{"ip": info.IP, "location": buildLocation(info)}, nil
	}
	return nil, ipc.NewError(ipc.ErrInternal, "all exit check endpoints failed")
}

func buildLocation(info ipInfo) string {
	location := info.City
	if info.Region != "" {
		if location != "" {
			location += ", " + info.Region
		} else {
			location = info.Region
		}
	}
	if info.Country != "" {
		if location != "" {
			location += ", " + info.Country
		} else {
			location = info.Country
		}
	}
	return location
}

func init() {
	ipc.Register(&TestService{})
}
