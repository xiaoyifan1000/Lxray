// subscription.go - 订阅拉取服务
//
// Fetch: 经本地 xray socks(127.0.0.1:10808) 代理拉取订阅内容。
// 用途: 部分订阅服务器国内直连不通, 但主进程 xray(本地代理模式)始终在跑,
//       其出站走选中节点, 因此经它中转可到达任意可达节点网络
package services

import (
	"encoding/json"
	"io"
	"net/http"
	"time"

	"golang.org/x/net/proxy"

	"vpnapp/core/ipc"
)

type SubscriptionService struct{}

type subscriptionFetchParams struct {
	Url string `json:"url"`
}

func (s *SubscriptionService) Name() string { return "SubscriptionService" }

func (s *SubscriptionService) Invoke(method string, params json.RawMessage) (any, error) {
	switch method {
	case "Fetch":
		var p subscriptionFetchParams
		if err := parseParams(params, &p); err != nil {
			return nil, err
		}
		if p.Url == "" {
			return nil, ipc.NewError(ipc.ErrBadParams, "url is required")
		}
		return s.fetch(p.Url)
	default:
		return nil, ipc.NewError(ipc.ErrBadRequest, "unknown method SubscriptionService."+method)
	}
}

func (s *SubscriptionService) fetch(url string) (any, error) {
	dialer, err := proxy.SOCKS5("tcp", "127.0.0.1:10808", nil, proxy.Direct)
	if err != nil {
		return nil, ipc.WrapError(ipc.ErrInternal, err)
	}
	ctxDialer, ok := dialer.(proxy.ContextDialer)
	if !ok {
		return nil, ipc.NewError(ipc.ErrInternal, "dialer does not support context dialing")
	}
	client := &http.Client{
		Transport: &http.Transport{
			DialContext: ctxDialer.DialContext,
		},
		Timeout: 25 * time.Second,
	}
	resp, err := client.Get(url)
	if err != nil {
		return nil, ipc.WrapError(ipc.ErrInternal, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, ipc.NewError(ipc.ErrInternal, "subscription http "+resp.Status)
	}
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, ipc.WrapError(ipc.ErrInternal, err)
	}
	return map[string]any{"body": string(body)}, nil
}

func init() {
	ipc.Register(&SubscriptionService{})
}
