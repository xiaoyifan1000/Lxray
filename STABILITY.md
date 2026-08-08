# VPNApp 稳定性测试记录

## 监控手段（已有能力）

1. **运行时状态**：`StatusService.Get` 返回 goroutines / heapAllocMB / numGC / lastGCPauseMs / uptimeMs
   - 日志入口：启动时 bootstrap 输出一次；可扩展为周期采样
2. **统一日志**：`LogService.Recent(limit)` 取 ring buffer 最近 1000 条；日志文件按日滚动
3. **崩溃**：hiAppEvent APP_CRASH 监听写入统一日志；Go 侧 panic 自动写 crash_*.txt
4. **隧道流量**：vpn-tun 接口字节 + xray 内核计数器双通道

## 建议测试流程（人工/自动化）

### 长时间运行内存监控
- 连接 VPN → 每 10 分钟记录 `StatusService.Get` 的 heapAllocMB / goroutines
- 判断标准：4 小时内 heap 无持续上升趋势（GC 正常回收）；goroutines 稳定
- 执行：`hilog -D 0x3200 | grep "core status"` 已有启动基线

### 反复启停（泄漏检查）
- 脚本化：连接→断开 100 次，观察:
  - 每次启停后 `StatusService.Get` 的 goroutines 不持续增长
  - Go 侧 CoreService 每次重启已 `runtime.GC() + debug.FreeOSMemory()`
  - vpn 进程退出后 `pidof com.example.vpnapp:vpn` 应为空（onDestroy 整进程退出）

### 断网/弱网
- 断 WiFi → 观察: 自动重连日志（`auto reconnect in Xms (attempt n/3)`）
- 恢复网络 → 3 次重试内应恢复 Connected

### 历史实测结论（截至本次开发）
- 真机 30+ 节点订阅导入、vmess 全链路、反复启停、强制杀进程恢复均已验证通过
- 主进程 TLS 崩溃问题（musl 主线程）已通过 worker 线程修复，稳定性回归通过
