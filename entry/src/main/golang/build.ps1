<#
build.ps1 - Go 核心�?libcore.so)交叉编译脚本

工具�? GOOS=android + OHOS NDK clang (--target=*-linux-ohos, musl)
  - netgo: 规避 musl �?net/cgo 类型冲突, 使用�?Go DNS 解析�?  - android_stub/: GOOS=android �?android/log.h �?-llog 的依赖桩(映射�?hilog)
  - ldflags "-w": 保留符号表以�?addr2line 定位崩溃; release 可加�?"-s"
用法: build.ps1 [-Abi arm64|x86_64|all] [-NdkHome <path>]
#>
param(
    [string]$NdkHome = $env:OHOS_NDK_HOME,
    [ValidateSet("arm64", "x86_64", "all")]
    [string]$Abi = "all",
    [string]$DevEcoHome = ""
)

$ErrorActionPreference = "Stop"

$GoExe = "go"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$LibsRoot = [System.IO.Path]::GetFullPath((Join-Path $ScriptDir "..\..\..\libs"))

function Find-NdkHome {
    if ($NdkHome -and (Test-Path (Join-Path $NdkHome "llvm\bin\clang.exe"))) { return $NdkHome }
    if ($DevEcoHome -eq "") {
        $envDirs = @($env:DEVECO_SDK_HOME, $env:DEVECO_STUDIO)
        foreach ($d in $envDirs) {
            if ($d -and (Test-Path (Join-Path $d "sdk\default\openharmony\native\llvm\bin\clang.exe"))) {
                $DevEcoHome = $d
                break
            }
        }
    }
    if ($DevEcoHome -ne "") {
        $cand = Join-Path $DevEcoHome "sdk\default\openharmony\native"
        if (Test-Path (Join-Path $cand "llvm\bin\clang.exe")) { return $cand }
    }
    $common = @(
        "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native",
        (Join-Path $env:ProgramFiles "Huawei\DevEco Studio\sdk\default\openharmony\native"),
        "D:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native",
        "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\native"
    )
    foreach ($c in $common) {
        if (Test-Path (Join-Path $c "llvm\bin\clang.exe")) { return $c }
    }
    return $null
}

$NdkHome = Find-NdkHome
if (-not $NdkHome) {
    throw "未找�?OHOS NDK，请设置 OHOS_NDK_HOME �?DevEco SDK 路径(可用 -DevEcoHome �?-NdkHome 参数)"
}

if (-not (Test-Path (Join-Path $NdkHome "llvm\bin\clang.exe"))) {
    throw "clang.exe not found in $(Join-Path $NdkHome 'llvm\bin')"
}

$fso = New-Object -ComObject Scripting.FileSystemObject
$clangShort = ($fso.GetFile((Join-Path $NdkHome "llvm\bin\clang.exe"))).ShortPath
if ($clangShort -match ' ') {
    $linkRoot = Join-Path $env:LOCALAPPDATA "Temp\lxray\ohos-ndk"
    if (-not (Test-Path (Join-Path $linkRoot "llvm\bin\clang.exe"))) {
        if (Test-Path $linkRoot) { Remove-Item -Force -Recurse $linkRoot }
        New-Item -ItemType Junction -Path $linkRoot -Target $NdkHome | Out-Null
    }
    $NdkHome = $linkRoot
    Write-Host "using junction NDK path: $NdkHome"
}

$LlvmBin = Join-Path $NdkHome "llvm\bin"
$Sysroot = (Join-Path $NdkHome "sysroot") -replace '\\', '/'

$env:CC = ($fso.GetFile((Join-Path $LlvmBin "clang.exe"))).ShortPath
$env:CXX = ($fso.GetFile((Join-Path $LlvmBin "clang++.exe"))).ShortPath
$env:AR = ($fso.GetFile((Join-Path $LlvmBin "llvm-ar.exe"))).ShortPath
$env:LD = ($fso.GetFile((Join-Path $LlvmBin "ld.lld.exe"))).ShortPath
if ($env:CC -match ' ') { $env:CC = (Join-Path $LlvmBin "clang.exe") }
if ($env:CXX -match ' ') { $env:CXX = (Join-Path $LlvmBin "clang++.exe") }
if ($env:AR -match ' ') { $env:AR = (Join-Path $LlvmBin "llvm-ar.exe") }
if ($env:LD -match ' ') { $env:LD = (Join-Path $LlvmBin "ld.lld.exe") }

$env:CGO_ENABLED = "1"
$env:GOOS = "android"
$env:CGO_CFLAGS_ALLOW = ".*"
$env:CGO_LDFLAGS_ALLOW = ".*"

$StubInclude = (Join-Path $ScriptDir "third_party\android_stub") -replace '\\', '/'
$StubLibRoot = Join-Path $ScriptDir "third_party\android_stub\lib"

$targets = @()
if ($Abi -eq "all") {
    $targets += @{ abi = "arm64-v8a"; goarch = "arm64"; triple = "aarch64-linux-ohos" }
    $targets += @{ abi = "x86_64"; goarch = "amd64"; triple = "x86_64-linux-ohos" }
} elseif ($Abi -eq "arm64") {
    $targets += @{ abi = "arm64-v8a"; goarch = "arm64"; triple = "aarch64-linux-ohos" }
} else {
    $targets += @{ abi = "x86_64"; goarch = "amd64"; triple = "x86_64-linux-ohos" }
}

Push-Location $ScriptDir
try {
    foreach ($t in $targets) {
        Write-Host "=== building $($t.abi) ($($t.goarch)) ==="

        $stubLibDir = (Join-Path $StubLibRoot $t.abi) -replace '\\', '/'
        $stubLib = Join-Path $StubLibRoot "$($t.abi)\liblog.a"
        if (-not (Test-Path $stubLib)) {
            New-Item -ItemType Directory -Force -Path (Join-Path $StubLibRoot $t.abi) | Out-Null
            $stubSrc = Join-Path $StubLibRoot "stub.c"
            Set-Content -Path $stubSrc -Value "void vpnapp_android_log_stub(void) {}"
            & $env:CC --target=$($t.triple) --sysroot=$Sysroot -c $stubSrc -o (Join-Path $StubLibRoot "$($t.abi)\stub.o")
            if ($LASTEXITCODE -ne 0) { throw "stub compile failed for $($t.abi)" }
            & $env:AR rcs $stubLib (Join-Path $StubLibRoot "$($t.abi)\stub.o")
            if ($LASTEXITCODE -ne 0) { throw "stub archive failed for $($t.abi)" }
        }

        $env:GOARCH = $t.goarch
        $env:CGO_CFLAGS = "-g -O2 --target=$($t.triple) --sysroot=$Sysroot -I$StubInclude"
        $env:CGO_LDFLAGS = "--target=$($t.triple) -fuse-ld=lld -L$stubLibDir -lhilog_ndk.z"
        $env:CFLAGS = "--target=$($t.triple) --sysroot=$Sysroot -D__MUSL__"
        $env:CXXFLAGS = $env:CFLAGS

        & $GoExe build -tags "netgo timetzdata" -ldflags "-w" -buildmode=c-shared -o libcore.so .
        if ($LASTEXITCODE -ne 0) { throw "go build failed for $($t.abi)" }
        if (Test-Path "libcore.h") { Remove-Item "libcore.h" }

        $outDir = Join-Path $LibsRoot $t.abi
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        Move-Item -Force "libcore.so" (Join-Path $outDir "libcore.so")
        Write-Host "OK: $(Join-Path $outDir 'libcore.so')"
    }
} finally {
    Pop-Location
}
