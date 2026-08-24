<#
.SYNOPSIS
    Build a Windows release and compile an Anx Reader GX Preview installer.

.DESCRIPTION
    Requires Inno Setup 6 (ISCC.exe). Stages files under build/windows/installer_staging
    and writes a versioned installer under build/windows/installer_output.

.PARAMETER SkipBuild
    Skip flutter build; use existing build/windows/x64/runner/Release.

.PARAMETER Flutter
    Path to flutter.bat (default: flutter on PATH).

.PARAMETER Iscc
    Full path to Inno Setup ISCC.exe. If omitted, searches PATH and default install locations.
#>
[CmdletBinding()]
param(
    [switch] $SkipBuild,
    [string] $Flutter = "flutter",
    [string] $Iscc = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $repoRoot

$iscc = $null
if ($Iscc) {
    if (Test-Path $Iscc) { $iscc = (Resolve-Path $Iscc).Path }
}
if (-not $iscc) {
    $cmd = Get-Command "ISCC.exe" -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) {
    $innoCandidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
        "${env:LocalAppData}\Programs\Inno Setup 6\ISCC.exe",
        "E:\Inno Setup 6\ISCC.exe"
    )
    foreach ($d in @("C:", "D:", "E:")) {
        $p = Join-Path "${d}\Inno Setup 6" "ISCC.exe"
        $innoCandidates += $p
    }
    $iscc = $innoCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $iscc) {
    $innoReg = Get-ItemProperty @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    ) -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -match '^Inno Setup' -and $_.InstallLocation } |
    Select-Object -First 1
    if ($innoReg.InstallLocation) {
        $guess = Join-Path $innoReg.InstallLocation.TrimEnd('\') "ISCC.exe"
        if (Test-Path $guess) { $iscc = $guess }
    }
}
if (-not $iscc) {
    Write-Error @"
未找到 Inno Setup 6 的 ISCC.exe。请先安装 Inno Setup（含命令行编译器），然后重试。

安装方式（任选其一，通常需要管理员权限）：
  - 官方安装包：https://jrsoftware.org/isdl.php  （安装时勾选 “Inno Setup Preprocessor” 等默认组件即可）
  - 管理员 PowerShell：winget install -e --id JRSoftware.InnoSetup

安装完成后 ISCC 一般在：
  ${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe

若 ISCC 不在默认路径，请显式传入，例如：
  .\scripts\build_windows_installer.ps1 -Iscc 'D:\tools\Inno Setup 6\ISCC.exe'
"@
}

$releaseDir = Join-Path $repoRoot "build\windows\x64\runner\Release"
$stagingDir = Join-Path $repoRoot "build\windows\installer_staging"
$installerOut = Join-Path $repoRoot "build\windows\installer_output"

if (-not $SkipBuild) {
    $env:DART_SUPPRESS_ANALYTICS = "true"
    & $Flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    & $Flutter build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not (Test-Path (Join-Path $releaseDir "anx_reader_gx_preview.exe"))) {
    Write-Error "Release build not found: $releaseDir\anx_reader_gx_preview.exe. Run without -SkipBuild or build first."
}

Remove-Item $stagingDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $stagingDir | Out-Null
# Robocopy is more reliable than Copy-Item for deep trees (avoids "already exists" on data\).
& robocopy.exe $releaseDir $stagingDir /E /NJH /NJS /NDL /NFL /nc /ns /np | Out-Null
if ($LASTEXITCODE -ge 8) {
    Write-Error "robocopy from Release to staging failed with exit code $LASTEXITCODE"
}

$iconSrc = Join-Path $repoRoot "windows\runner\resources\app_icon.ico"
if (-not (Test-Path $iconSrc)) {
    Write-Error "Missing icon: $iconSrc"
}
Copy-Item $iconSrc (Join-Path $stagingDir "logo.ico") -Force

$extraNative = Join-Path $repoRoot "scripts\windows\x64"
if (Test-Path $extraNative) {
    Copy-Item -Path (Join-Path $extraNative "*") -Destination $stagingDir -Recurse -Force
}

Remove-Item $installerOut -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $installerOut | Out-Null

$pubspecPath = Join-Path $repoRoot "pubspec.yaml"
$versionLine = (Get-Content $pubspecPath -Raw) -match '(?m)^version:\s*(\S+)'
if (-not $matches) {
    Write-Error "Could not parse version from pubspec.yaml"
}
$appVersion = ($matches[1] -split '\+')[0]

# ISCC.exe lives in the Inno install root (e.g. E:\Inno Setup 6\ISCC.exe → ...\Languages)
# We vendor Chinese *.isl under scripts/ and reference them from the .iss,
# so we don't need to copy files into the Inno Setup installation.

$issPath = Join-Path $repoRoot "scripts\compile_windows_setup-inno.iss"
$installerBaseName = "Anx-Reader-GX-Preview-windows-$appVersion-setup"
& $iscc `
    "/DStagingDir=$stagingDir" `
    "/DInstallerOutputDir=$installerOut" `
    "/DMyAppVersion=$appVersion" `
    "/F$installerBaseName" `
    $issPath
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$installerFileName = "$installerBaseName.exe"
$installerExe = Join-Path $installerOut $installerFileName
if (-not (Test-Path $installerExe)) {
    Write-Error "Inno Setup did not produce: $installerExe"
}

Write-Host ""
Write-Host "Installer ready: $installerExe" -ForegroundColor Green
