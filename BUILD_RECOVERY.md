# Lxray 构建复原指南（Build Recovery Guide）

本仓库仅包含**源码**。请按本指南 + 下方"给 AI 的提示"重建完整可构建工程。

## 1. 环境要求

| 依赖 | 版本 | 说明 |
|------|------|------|
| DevEco Studio | 5.x+ (SDK 6.1.1 / API 24) | 鸿蒙应用开发环境 |
| Go 工具链 | go 1.26+ | 编译 libcore.so（Xray 内核） |
| OHOS NDK | DevEco 自带 | 交叉编译 Go 为 OHOS 动态库 |

## 2. 目录结构（源码部分）

```
VPNApp/
├── AppScope/                     # 应用级资源（名称 Lxray、图标）
├── entry/src/main/ets/           # ArkTS UI + 业务逻辑
│   ├── pages/                    # 主页/节点/设置
│   ├── lib/                      # 桥接封装、状态机、存储、解析器
│   └── vpnability/               # VPN 扩展能力（:vpn 独立进程）
├── entry/src/main/cpp/           # C++ NAPI 桥接层（worker 线程进 Go）
├── entry/src/main/golang/        # Go 核心（Xray 封装、服务、构建脚本）
├── entry/src/main/resources/     # 资源（rawfile 含 config.json/geoip/geosite）
├── Xray-core-26.3.27/            # Xray 源码（含鸿蒙补丁，见下）
├── build-all.ps1                 # 一键构建脚本（路径自动探测）
└── build-profile.json5           # 应用构建配置（签名需自行配置）
```

## 3. 构建流程

```
1. DevEco Studio 打开项目 → 配置自动签名（File → Project Structure → Signing Configs）
2. 编译 Go 内核（自动执行）:
   powershell -ExecutionPolicy Bypass -File build-all.ps1
   或手动: powershell -File entry/src/main/golang/build.ps1 [-Abi arm64|x86_64|all]
3. DevEco 里 Run / 或 hvigor 命令行打包
```

## 4. 关键技术点（改动过的部分，别覆盖）

### 4.1 Xray 鸿蒙补丁（重要！）
`Xray-core-26.3.27/proxy/tun/tun_android.go` 被重写：
- 原版用 gvisor `fdbased.New()`，其对 tun fd 调 `fstat` → 鸿蒙内核返回 **EPERM**
- 补丁改为直接用 `unix.Read/Write` + xray 自带 `LinkEndpoint`（参考 Darwin 实现）
- **升级 Xray 时此补丁需重新应用**

### 4.2 Go 交叉编译（golang/build.ps1）
- `GOOS=android GOARCH=arm64` + OHOS NDK clang（`--target=aarch64-linux-ohos --sysroot=<ndk>/sysroot -D__MUSL__`）
- `-tags netgo`（规避 musl 下 net/cgo 类型冲突）
- `android_stub/`：提供 `android/log.h` stub 映射到 hilog + 空 `liblog.a`（GOOS=android 的链接依赖）
- `CGO_LDFLAGS_ALLOW=.*`（Go 1.26 cgo flag 白名单绕过）
- 路径含空格 → 自动创建 junction

### 4.3 鸿蒙 musl TLS 限制（架构约束）
- 鸿蒙 musl 主线程 TLS 布局与 pthread 线程不同，Go c-shared 在主线程进入会 SIGSEGV
- **所有 GoInvoke 必须经 C++ 桥接层的专用 worker 线程**（`cpp/bridge.cpp`）——不要改成主线程直调

### 4.4 签名
- `build-profile.json5` 中 signingConfigs 是**个人密钥**，已从仓库移除
- 每个人用 DevEco 自动签名重新生成（debug 够用；发布需正式证书）

## 5. 常见坑

| 现象 | 原因 | 解决 |
|------|------|------|
| libcore.so 加载失败 | 未先编译 Go 内核 | 先跑 build.ps1 再构建 |
| dlopen 失败 LIB_NOT_LOADED | libs/ 目录为空 | 确保 libcore.so 已生成 |
| VPN 无法启动 "未选择节点" | 需要先导入节点 | 节点页粘贴 vless:// 链接或订阅 |
| tun fd fstat EPERM | Xray 补丁未应用 | 检查 tun_android.go 是否为直写版本 |
| 断线重连不生效 | 未选择节点 | 选择节点后再连 |
| IPv6 网站走真实 IP | 平台限制 | 鸿蒙 VPN v6 支持不成熟，已知限制 |

## 6. 给 AI 的提示（供使用者粘贴给 AI 助手）

> 这是一个鸿蒙 (HarmonyOS) VPN 客户端项目。架构：ArkTS UI → C++ NAPI 桥接 → Go 编译的
> Xray-core 动态库。构建链：Go 交叉编译 libcore.so（GOOS=android + OHOS NDK clang，
> 见 entry/src/main/golang/build.ps1），然后 DevEco 打包。关键点：
> 1) Xray tun_android.go 有鸿蒙补丁（fd 直写，不用 fdbased）
> 2) 所有 Go 调用必须走 cpp/bridge.cpp 的 worker 线程（鸿蒙 musl TLS 限制）
> 3) 签名用 DevEco 自动签名
> 请帮我：检查当前环境是否满足构建条件，执行 build-all.ps1，或解释任何构建错误。

## 7. 已排除（不随源码上传）

- 签名密钥（.ohos/config）、build-profile.json5 的 signingConfigs
- 构建产物（entry/libs/*.so、entry/build、entry/.cxx）
- 本机配置（local.properties、oh_modules、.hvigor、.idea）
- 截图（shots/、*.jpeg）
