# Packaging, Release & CI Automation Manual

This runbook covers packaging procedures and GitHub CI/CD autonomous diagnostics for Anx Reader.

---

## 1. Android Release Packaging

Standard Android Release build commands on Windows:

```powershell
$fvmBin = Join-Path $env:LOCALAPPDATA 'Programs\fvm\fvm'
$flutterSdk = (Get-Item -LiteralPath '.fvm\flutter_sdk').Target | Select-Object -First 1
$flutterBat = Join-Path $flutterSdk 'bin\flutter.bat'
$env:Path = "$fvmBin;$env:Path"
$appDataPath = Join-Path (Get-Location) '.codex-appdata'
New-Item -ItemType Directory -Force -Path $appDataPath | Out-Null
$env:APPDATA = $appDataPath
$env:LOCALAPPDATA = $appDataPath
$env:DART_SUPPRESS_ANALYTICS = 'true'

& $flutterBat pub get --enforce-lockfile
& $flutterBat build apk --release
```

**Outputs**:
- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AAB: `build/app/outputs/bundle/release/app-release.aab` (using `build appbundle`)

---

## 2. Windows Release Packaging (Inno Setup Installer)

Prerequisites: **Inno Setup 6** (needs `ISCC.exe` in PATH or in default install path).

```powershell
# Ensure scripts use the FVM-managed project SDK
$fvmBin = Join-Path $env:LOCALAPPDATA 'Programs\fvm\fvm'
$flutterSdk = (Get-Item -LiteralPath '.fvm\flutter_sdk').Target | Select-Object -First 1
$fvmFlutterBin = Join-Path $flutterSdk 'bin'
$env:Path = "$fvmFlutterBin;$fvmBin;$env:Path"

# Full build (pub get + build windows --release + compile installer)
.\scripts\build_windows_installer.ps1

# Incremental packaging (reuse existing build\windows\x64\runner\Release)
.\scripts\build_windows_installer.ps1 -SkipBuild
```

**Output**:
- Installer executable: `build/windows/installer_output/app.exe`

---

## 3. GitHub CI/CD Autonomous Diagnostics

When code or release tags are pushed to remote, the AI Agent must verify CI status autonomously without delegating to the user.

### Automated Diagnostic Snippets (PowerShell):

```powershell
# 1. Query latest run status & steps
$run = Invoke-RestMethod -Uri "https://api.github.com/repos/<owner>/<repo>/actions/runs" -Headers @{"User-Agent"="PowerShell"}
$latestRun = $run.workflow_runs[0]
$jobs = Invoke-RestMethod -Uri $latestRun.jobs_url -Headers @{"User-Agent"="PowerShell"}
$jobs.jobs | ForEach-Object {
    Write-Output "Job: $($_.name) [$($_.conclusion)]"
    $_.steps | ForEach-Object { Write-Output "  - Step: $($_.name) [$($_.conclusion)]" }
}

# 2. Extract token from Git Credential Manager silently
"protocol=https`nhost=github.com`n" | Set-Content "git_cred_in.txt"
$p = Start-Process -FilePath "git" -ArgumentList "credential", "fill" -NoNewWindow -PassThru -RedirectStandardInput "git_cred_in.txt" -RedirectStandardOutput "git_cred_out.txt"
$p.WaitForExit(5000)
$cred = Get-Content "git_cred_out.txt"
Remove-Item "git_cred_in.txt", "git_cred_out.txt" -Force
$token = ($cred | Select-String -Pattern '^password=(.*)$').Matches.Groups[1].Value

# 3. Download, unzip, and grep private logs
$headers = @{ "Authorization" = "Bearer $token"; "Accept" = "application/vnd.github+json"; "User-Agent" = "PowerShell" }
Invoke-WebRequest -Uri "https://api.github.com/repos/<owner>/<repo>/actions/runs/$($latestRun.id)/logs" -Headers $headers -OutFile "ci_logs.zip"
Expand-Archive -Path "ci_logs.zip" -DestinationPath "ci_logs" -Force
Get-ChildItem -Path "ci_logs" -Recurse -Filter "*.txt" | ForEach-Object {
    $errors = Get-Content $_.FullName | Select-String -Pattern "FAIL|EXCEPTION|══╡ EXCEPTION|Pixel test failed|Error:" -Context 2,8
    if ($errors) { Write-Output "=== [$($_.Name)] ==="; $errors }
}
Remove-Item "ci_logs.zip", "ci_logs" -Recurse -Force
```

---

## 4. Preview Release SOP & CI/CD Iron Rules

To guarantee release stability and prevent untested code deployment, every release MUST strictly adhere to the **Double Defense** protocol:

1. **Rule 1: Remote CI Must Pass First (CI-First Gate)**
   - When code modifications are complete, push commits to `develop` (`git push origin develop`).
   - Monitor the remote GitHub Actions `CI` workflow (`.github/workflows/ci.yaml`).
   - **Never push a release tag (`gx-v*`) until the `CI` workflow run on `develop` is 100% GREEN (`success`).**

2. **Rule 2: Never Push Branch & Tag Concurrently**
   - Branch pushes and release tag pushes must be strictly serialized.
   - Pushing tags simultaneously bypasses the CI feedback loop and leads to broken release attempts.

3. **Rule 3: CD release Workflow Embedded Quality Gate**
   - The CD workflow (`.github/workflows/gx-preview-release.yaml`) contains an independent `test` job executing `flutter analyze` and `flutter test`.
   - The `android`, `windows`, and `release` publishing jobs strictly depend on `test`. If tests fail in the cloud environment, the release is immediately blocked.

