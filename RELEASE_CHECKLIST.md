# VPNApp 发布检查清单

## A. 功能收尾
- [ ] 确认"应用名/图标"正式化（当前 label=VPNApp，图标为模板，需替换 `AppScope/resources` 与 `entry/resources` 的 startIcon/layered_image）
- [ ] 应用版本号：`AppScope/app.json5` versionCode/versionName 按发布策略设置
- [ ] release 构建产物验证（`build-all.ps1 -BuildMode release`）

## B. 签名与上架
- [ ] 正式签名证书（当前为 debug 自动签名）
- [ ] AGC 创建应用，bundleName 复核 `com.example.vpnapp`
- [ ] 上架资料：截图、简介（强调"仅客户端框架，不提供服务器"）
- [ ] 隐私政策接入 AGC（PRIVACY.md 完善后）
- [ ] 受限权限复核：MANAGE_VPN 未声明（实测无需），KEEP_BACKGROUND_RUNNING 为 normal 级

## C. 合规风险点（务必自查）
- [ ] 不内置任何节点/订阅（当前 rawfile/config.json 含测试节点，**发布前必须清空出站**）
- [ ] 不提供服务器购买/推荐功能
- [ ] 用户协议：明确"用户自备节点，责任自负"

## D. 平台限制备忘（已知不可做）
- 关窗保活：长时任务被系统校验拒绝（MODE_TASK_KEEPING 等全部 9800005）
- 清除/设置系统代理：无三方 API（仅企业 MDM 有）
- 全局悬浮球/实况窗：系统应用专属
- 枚举已安装应用：受限权限（应用分流已移除）
- 三方应用无法自动设置系统代理；"仅指定应用使用"= 不开 VPN + 手动配置应用代理

## E. 发布前清理项
- [ ] 移除调试残留：go_stderr.log 重定向说明、PingService.Panic（如需保留注明）
- [ ] rawfile/config.json 中的测试订阅地址清理
- [ ] 设置页"关于"版本信息核对
