// ipc.go - Go 侧 IPC 服务注册表与统一错误契约
//
// 响应契约: {"success":bool, "data":..., "error":{"code","message","detail"}}
// 服务通过 Register 注册, Invoke 按 "Service.Method" 分发;
// 该注册表非并发安全, 调用串行化由桥接层 worker 线程保证
package ipc

import (
	"encoding/json"
	"fmt"
)

const (
	ErrBadRequest     = "BAD_REQUEST"
	ErrUnknownService = "UNKNOWN_SERVICE"
	ErrBadParams      = "BAD_PARAMS"
	ErrInternal       = "INTERNAL"
	ErrPanic          = "PANIC"
	ErrNotReady       = "NOT_READY"
)

type Error struct {
	Code    string `json:"code"`
	Message string `json:"message"`
	Detail  string `json:"detail,omitempty"`
}

func (e *Error) Error() string {
	return fmt.Sprintf("%s: %s", e.Code, e.Message)
}

func NewError(code, message string) *Error {
	return &Error{Code: code, Message: message}
}

func WrapError(code string, err error) *Error {
	if err == nil {
		return nil
	}
	if ie, ok := err.(*Error); ok {
		return ie
	}
	return &Error{Code: code, Message: err.Error()}
}

type Response struct {
	Success bool            `json:"success"`
	Data    json.RawMessage `json:"data,omitempty"`
	Error   *Error          `json:"error,omitempty"`
}

func OK(data any) *Response {
	raw, err := json.Marshal(data)
	if err != nil {
		return Fail(WrapError(ErrInternal, err))
	}
	return &Response{Success: true, Data: raw}
}

func Fail(err *Error) *Response {
	return &Response{Success: false, Error: err}
}

type Service interface {
	Name() string
	Invoke(method string, params json.RawMessage) (any, error)
}

var services = map[string]Service{}

func Register(s Service) {
	services[s.Name()] = s
}

func Invoke(serviceMethod string, params json.RawMessage) *Response {
	name, method := splitServiceMethod(serviceMethod)
	if name == "" || method == "" {
		return Fail(NewError(ErrBadRequest, "service must be in form 'Service.Method', got: "+serviceMethod))
	}
	s, ok := services[name]
	if !ok {
		known := make([]string, 0, len(services))
		for k := range services {
			known = append(known, k)
		}
		return Fail(&Error{Code: ErrUnknownService, Message: "unknown service: " + name, Detail: fmt.Sprintf("registered: %v", known)})
	}
	data, err := s.Invoke(method, params)
	if err != nil {
		return Fail(WrapError(ErrInternal, err))
	}
	return OK(data)
}

func splitServiceMethod(s string) (string, string) {
	for i := 0; i < len(s); i++ {
		if s[i] == '.' {
			return s[:i], s[i+1:]
		}
	}
	return "", ""
}
