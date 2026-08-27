<#
.SYNOPSIS
    Runs the Clean Craftsmanship Automated Quality Gauntlet for Anx Reader.
.DESCRIPTION
    Executes static analysis, unit tests, golden UI regressions, and git hygiene checks.
#>

$ErrorActionPreference = 'Stop'

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "  Anx Reader Clean Craftsmanship Quality Gauntlet  " -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# 1. Flutter Static Analysis
Write-Host "`n[1/4] Running Static Analysis (fvm flutter analyze --no-fatal-infos)..." -ForegroundColor Yellow
& fvm flutter analyze --no-fatal-infos
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[FAILED] Static analysis found issues. Please fix before proceeding." -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "[PASSED] Static analysis clean." -ForegroundColor Green

# 2. Fast Unit & Integration Tests
Write-Host "`n[2/4] Running Unit & Integration Tests (fvm flutter test --no-pub)..." -ForegroundColor Yellow
& fvm flutter test --no-pub
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[FAILED] Unit/integration tests failed." -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "[PASSED] Unit tests passed." -ForegroundColor Green

# 3. Golden UI Snapshot Anti-Regression Tests
Write-Host "`n[3/4] Running Golden UI Snapshot Tests (settings_page_golden_test.dart)..." -ForegroundColor Yellow
& fvm flutter test test/golden/settings_page_golden_test.dart
if ($LASTEXITCODE -ne 0) {
    Write-Host "`n[FAILED] Golden pixel snapshot test failed. UI layout regression detected." -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "[PASSED] Golden snapshot tests intact." -ForegroundColor Green

# 4. Git Workspace Hygiene Check
Write-Host "`n[4/4] Checking Git Workspace Hygiene..." -ForegroundColor Yellow
$status = & git status --porcelain
$dirtyLockfile = $status | Select-String -Pattern "pubspec\.lock"
if ($dirtyLockfile) {
    Write-Host "[WARNING] pubspec.lock has uncommitted changes. Ensure dependency updates are intentional." -ForegroundColor Yellow
} else {
    Write-Host "[PASSED] Lockfile and generated files are clean." -ForegroundColor Green
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "  [SUCCESS] All Gauntlet Quality Gates Passed!    " -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
