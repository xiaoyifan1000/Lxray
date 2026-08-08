<#
pre-upload-check.ps1 - Pre-upload privacy check

Checks:
  1. signing key block in build-profile.json5 (plaintext passwords / local paths)
  2. personal info in source (username / paths / test node credentials / sub token)
  3. leftover build artifacts / screenshots

Usage: powershell -ExecutionPolicy Bypass -File pre-upload-check.ps1 [-Clean]
  -Clean: auto-remove signing block from build-profile.json5 (backup to .bak first)
#>
param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$issues = @()

# 1. signing key block
$bp = Join-Path $Root "build-profile.json5"
$content = Get-Content $bp -Raw
if ($content -match '"signingConfigs"\s*:') {
    $issues += "build-profile.json5 contains signing keys (plaintext passwords). MUST remove before upload."
    if ($Clean) {
        Copy-Item $bp "$bp.bak" -Force
        $json = $content -replace '(?s)"signingConfigs"\s*:\s*\[.*?\],', '"signingConfigs": [],'
        Set-Content $bp $json -NoNewline
        Write-Host "Signing block removed. Backup: build-profile.json5.bak"
    }
}

# 2. personal info scan
# Replace the placeholders below with your own values before use,
# or add new patterns to extend coverage.
$sensitive = @("USERNAME_HERE", "YOUR_PROJECT_PATH", "YOUR_SERVER_IP", "YOUR_UUID",
    "YOUR_SUBSCRIPTION_TOKEN", "keyPassword", "storePassword", "signingConfigs")
$files = Get-ChildItem $Root -Recurse -File | Where-Object {
    $_.FullName -notmatch "build|\.hvigor|oh_modules|\.cxx|\.idea|\\shots\\|\.jpeg|\.png|\.so$|\.dat$|\.o$|\.a$|\.zip$|\.git|\.bak$|pre-upload-check\.ps1$"
}
foreach ($f in $files) {
    $c = Get-Content $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $c) { continue }
    foreach ($p in $sensitive) {
        if ($c.Contains($p)) {
            $issues += "$($f.FullName.Replace($Root,'')) contains: $p"
        }
    }
}

# 3. leftover files
$leftovers = @()
if (Test-Path (Join-Path $Root "entry\libs\arm64-v8a\libcore.so")) { $leftovers += "entry/libs/*.so build artifacts present" }
if (Test-Path (Join-Path $Root "shots")) { $leftovers += "shots/ screenshots dir present" }
Get-ChildItem $Root -Filter "*.jpeg" -ErrorAction SilentlyContinue | ForEach-Object { $leftovers += "root screenshot: $($_.Name)" }
$leftovers | ForEach-Object { $issues += $_ }

if ($issues.Count -eq 0) {
    Write-Host "OK - check passed, ready to upload"
} else {
    Write-Host "Issues found:"
    $issues | ForEach-Object { Write-Host "  [!] $_" }
    Write-Host "`nFix the issues above, then re-run; or use -Clean to auto-remove signing block"
}
