<#
build-all.ps1 - VPNApp 一键构建脚本

流程: Go 核心双 ABI 编译 -> hvigor 打包 -> 输出产物信息
用法: powershell -ExecutionPolicy Bypass -File build-all.ps1 [-Abi all|arm64|x86_64] [-BuildMode debug|release] [-DevEcoHome <path>]
前置: 已安装 Go, 已配置签名(build-profile.json5); DevEco 安装路径自动探测
#>
param(
    [ValidateSet("all", "arm64", "x86_64")]
    [string]$Abi = "all",
    [ValidateSet("debug", "release")]
    [string]$BuildMode = "debug",
    [string]$DevEcoHome = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$GoDir = Join-Path $Root "entry\src\main\golang"

# 自动探测 DevEco Studio 安装路径(支持参数覆盖)

function Find-DevEco {
    if ($DevEcoHome -ne "" -and (Test-Path $DevEcoHome)) { return $DevEcoHome }
    $candidates = @(
        "F:\lxray\DevEco Studio",
        (Join-Path $env:ProgramFiles "Huawei\DevEco Studio"),
        (Join-Path ${env:ProgramFiles(x86)} "Huawei\DevEco Studio"),
        "D:\Program Files\Huawei\DevEco Studio",
        "C:\Program Files\Huawei\DevEco Studio"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "tools\hvigor\bin\hvigorw.js")) { return $c }
    }
    $envPath = $env:DEVECO_STUDIO
    if ($envPath -and (Test-Path (Join-Path $envPath "tools\hvigor\bin\hvigorw.js"))) { return $envPath }
    return $null
}

$DevEco = Find-DevEco
if (-not $DevEco) {
    throw "未找到 DevEco Studio，请用 -DevEcoHome 参数指定安装路径"
}
$Jbr = Join-Path $DevEco "jbr\bin"
$Hvigor = Join-Path $DevEco "tools\hvigor\bin\hvigorw.js"
$SdkHome = Join-Path $DevEco "sdk"
Write-Host "DevEco Studio: $DevEco"

if (-not (Test-Path $Hvigor)) {
    throw "hvigorw.js not found: $Hvigor (检查 DevEco 安装路径)"
}

Write-Host "== 1/2 Go 核心编译 ($Abi) =="
Push-Location $GoDir
try {
    & powershell -ExecutionPolicy Bypass -File .\build.ps1 -Abi $Abi -DevEcoHome $DevEco
    if ($LASTEXITCODE -ne 0) { throw "go build failed" }
} finally {
    Pop-Location
}

Write-Host "== 2/2 hvigor 打包 ($BuildMode) =="
$env:PATH = "$Jbr;$env:PATH"
$env:DEVECO_SDK_HOME = $SdkHome
Push-Location $Root
try {
    & node $Hvigor --mode module -p product=default -p buildMode=$BuildMode -p module=entry@default assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw "hvigor build failed" }
} finally {
    Pop-Location
}

Write-Host "== 产物 =="
Get-ChildItem (Join-Path $Root "entry\build\default\outputs\default") -Filter "*.hap" | ForEach-Object {
    "{0}  {1:N1} MB" -f $_.Name, ($_.Length / 1MB)
}
Write-Host "构建完成"
