// xlog.go - Go 侧统一日志系统
//
// 三路输出: hilog(domain 0x3200, tag VPNAPP-GO) / 每日滚动文件 / 1000 条内存 ring buffer
//   - Init(dir) 前日志不丢: 先入 ring buffer, Init 时自动落盘
//   - 文件按天滚动(vpnapp_YYYYMMDD.log), CleanOld 负责保留期清理
//   - panic/crash 由 main.go 写入 crash_*.txt 到同一目录
package xlog

/*
#cgo LDFLAGS: -lhilog_ndk.z
#include <stdlib.h>
#include <hilog/log.h>

static void vpn_hilog(unsigned int level, unsigned int domain, const char* tag, const char* msg) {
    OH_LOG_Print(LOG_APP, (LogLevel)level, domain, tag, "%{public}s", msg);
}
*/
import "C"

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"
	"unsafe"
)

const (
	LevelDebug = 3
	LevelInfo  = 4
	LevelWarn  = 5
	LevelError = 6
	LevelFatal = 7
)

const (
	HiLogDomain = 0x3200
	HiLogTag    = "VPNAPP-GO"
)

const ringSize = 1000

type Entry struct {
	Time    string         `json:"time"`
	Level   int            `json:"level"`
	Module  string         `json:"module"`
	Message string         `json:"message"`
	Fields  map[string]any `json:"fields,omitempty"`
}

var (
	mu       sync.Mutex
	minLevel = LevelDebug
	ring     = make([]Entry, 0, ringSize)
	logDir   string
	logFile  *os.File
	logDay   string
)

func SetLevel(level int) {
	mu.Lock()
	defer mu.Unlock()
	minLevel = level
}

func GetLevel() int {
	mu.Lock()
	defer mu.Unlock()
	return minLevel
}

func LogDir() string {
	mu.Lock()
	defer mu.Unlock()
	return logDir
}

func Init(dir string) error {
	mu.Lock()
	defer mu.Unlock()
	if err := os.MkdirAll(dir, 0755); err != nil {
		return err
	}
	logDir = dir
	flushRingLocked()
	return nil
}

func Debug(module, msg string, fields map[string]any) { write(LevelDebug, module, msg, fields) }
func Info(module, msg string, fields map[string]any)  { write(LevelInfo, module, msg, fields) }
func Warn(module, msg string, fields map[string]any)  { write(LevelWarn, module, msg, fields) }
func Error(module, msg string, fields map[string]any) { write(LevelError, module, msg, fields) }

func WriteExternal(level int, module, msg string) {
	if level < LevelDebug || level > LevelFatal {
		level = LevelInfo
	}
	write(level, module, msg, nil)
}

func write(level int, module, msg string, fields map[string]any) {
	mu.Lock()
	defer mu.Unlock()
	if level < minLevel {
		return
	}
	e := Entry{
		Time:    time.Now().Format("2006-01-02 15:04:05.000"),
		Level:   level,
		Module:  module,
		Message: msg,
		Fields:  fields,
	}
	pushRingLocked(e)
	line := formatLine(e)
	cMsg := C.CString(line)
	cTag := C.CString(HiLogTag)
	C.vpn_hilog(C.uint(level), C.uint(HiLogDomain), cTag, cMsg)
	C.free(unsafe.Pointer(cMsg))
	C.free(unsafe.Pointer(cTag))
	writeFileLocked(line)
}

func pushRingLocked(e Entry) {
	if len(ring) >= ringSize {
		copy(ring, ring[1:])
		ring = ring[:ringSize-1]
	}
	ring = append(ring, e)
}

func Recent(limit int) []Entry {
	mu.Lock()
	defer mu.Unlock()
	if limit <= 0 || limit > len(ring) {
		limit = len(ring)
	}
	out := make([]Entry, limit)
	copy(out, ring[len(ring)-limit:])
	return out
}

func formatLine(e Entry) string {
	var sb strings.Builder
	sb.WriteString(e.Time)
	sb.WriteString(" ")
	sb.WriteString(levelName(e.Level))
	sb.WriteString(" [")
	sb.WriteString(e.Module)
	sb.WriteString("] ")
	sb.WriteString(e.Message)
	if len(e.Fields) > 0 {
		if raw, err := json.Marshal(e.Fields); err == nil {
			sb.WriteString(" ")
			sb.Write(raw)
		}
	}
	return sb.String()
}

func levelName(l int) string {
	switch l {
	case LevelDebug:
		return "D"
	case LevelInfo:
		return "I"
	case LevelWarn:
		return "W"
	case LevelError:
		return "E"
	case LevelFatal:
		return "F"
	}
	return "?"
}

func currentFileLocked() *os.File {
	if logDir == "" {
		return nil
	}
	day := time.Now().Format("20060102")
	if logFile != nil && logDay == day {
		return logFile
	}
	if logFile != nil {
		logFile.Close()
		logFile = nil
	}
	path := filepath.Join(logDir, fmt.Sprintf("vpnapp_%s.log", day))
	f, err := os.OpenFile(path, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0644)
	if err != nil {
		return nil
	}
	logFile = f
	logDay = day
	return logFile
}

func writeFileLocked(line string) {
	f := currentFileLocked()
	if f == nil {
		return
	}
	fmt.Fprintln(f, line)
}

func flushRingLocked() {
	for _, e := range ring {
		writeFileLocked(formatLine(e))
	}
}

func ListFiles() ([]string, error) {
	mu.Lock()
	defer mu.Unlock()
	if logDir == "" {
		return nil, nil
	}
	matches, err := filepath.Glob(filepath.Join(logDir, "*.log"))
	if err != nil {
		return nil, err
	}
	crashes, err := filepath.Glob(filepath.Join(logDir, "crash_*.txt"))
	if err != nil {
		return nil, err
	}
	return append(matches, crashes...), nil
}

func CleanOld(keepDays int) error {
	mu.Lock()
	defer mu.Unlock()
	if logDir == "" {
		return nil
	}
	cutoff := time.Now().AddDate(0, 0, -keepDays)
	entries, err := os.ReadDir(logDir)
	if err != nil {
		return err
	}
	for _, e := range entries {
		info, err := e.Info()
		if err != nil {
			continue
		}
		if info.ModTime().Before(cutoff) {
			os.Remove(filepath.Join(logDir, e.Name()))
		}
	}
	return nil
}
