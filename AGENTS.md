# AGENTS.md

This file provides working instructions for code agents in this repository.

## Project Summary

Anx Reader is a cross-platform Flutter e-book reader with EPUB/MOBI/AZW3/FB2/TXT/PDF support.

Key areas:
- `lib/`: Flutter app code
- `assets/foliate-js/`: JavaScript renderer used by the reader WebView
- `lib/service/book_player/`: local HTTP serving and reading bridge
- `lib/providers/`, `lib/models/`: Riverpod, Freezed, JSON-backed app state and models
- `lib/dao/database.dart`: SQLite schema and migrations

## Local Flutter SDK Management

This checkout uses FVM locally and is pinned to Flutter 3.35.3, matching the repository CI configuration.

- Use `fvm flutter ...` and `fvm dart ...` for project commands. Do not use the globally installed `flutter` or `dart` executables in this checkout.
- `.fvmrc`, `.fvm/`, `.vscode/`, and this `AGENTS.md` are intentionally ignored because this is a local setup for a repository the user does not own. Do not stage them or change the ignore rules unless the user explicitly asks.
- Do not run `flutter upgrade`, change the FVM project version, or set an FVM global Flutter version without explicit user approval.
- Run `fvm flutter pub get --enforce-lockfile` only when dependency resolution is required. The lockfile must not drift unless dependency updates are intentional.
- FVM 4.1.2 is installed under `%LOCALAPPDATA%\Programs\fvm\fvm`, and its shared SDK cache is `E:\FVM\cache`.
- `%LOCALAPPDATA%\Microsoft\WindowsApps\fvm.cmd` forwards to the installed `fvm.exe`, so the bare `fvm` command also works in terminals that still have the pre-install user PATH.
- Flutter 3.35.3's Windows script invokes `$git`; the SDK therefore keeps a minimal `$git.cmd` forwarder under the already-ignored `bin/mingit/cmd/` directory, which `flutter.bat` adds to PATH automatically.
- Restart VS Code terminals after changing the FVM version so the IDE-provided `flutter` command picks up the local SDK.

Flutter/GitHub downloads on this machine should explicitly use the local proxy without changing the global Git configuration:

```powershell
$proxy = 'http://127.0.0.1:7890'
$env:PUB_HOSTED_URL = 'https://pub.dev'
$env:FLUTTER_STORAGE_BASE_URL = 'https://storage.googleapis.com'
$env:HTTP_PROXY = $proxy
$env:HTTPS_PROXY = $proxy
$env:http_proxy = $proxy
$env:https_proxy = $proxy
$env:GRADLE_OPTS = '-Dhttp.proxyHost=127.0.0.1 -Dhttp.proxyPort=7890 -Dhttps.proxyHost=127.0.0.1 -Dhttps.proxyPort=7890'
$env:GIT_CONFIG_COUNT = '2'
$env:GIT_CONFIG_KEY_0 = 'http.proxy'
$env:GIT_CONFIG_VALUE_0 = $proxy
$env:GIT_CONFIG_KEY_1 = 'https.proxy'
$env:GIT_CONFIG_VALUE_1 = $proxy
```

## Build And Dev Commands

From the repo root:

```bash
# Resolve exactly the committed dependency graph when needed
fvm flutter pub get --enforce-lockfile

# Run on the currently connected Android test device without resolving dependencies again
fvm flutter run --no-pub -d FNENW19A18016816

# Run on Windows desktop (debug)
fvm flutter run -d windows

# Generate localization
fvm flutter gen-l10n

# Generate Riverpod / Freezed / JSON code
fvm dart run build_runner build --delete-conflicting-outputs
```

## UI And Automation Testing Workflows

### 1. Golden 像素快照测试（UI 排版防退化）

用于在不拉起完整桌面窗口的情况下，毫秒级验证关键页面/组件的排版、字号与布局完整性：

```bash
# 运行设置页等组件的 Golden 排版测试（毫秒级）
fvm flutter test test/golden/settings_page_golden_test.dart

# 更新基准快照图
fvm flutter test test/golden/settings_page_golden_test.dart --update-goldens
```

### 2. Windows 宿主级黑盒操控与截图（基于 uv）

当应用在 Windows 桌面上运行（`fvm flutter run -d windows`）时，可通过 Python 脚本发送系统级按键与截图指令（依赖通过 `uv` + PEP 723 自动隔离管理，无需配置 Python 环境）：

```powershell
# 实时捕获桌面 Anx Reader 窗口画面
uv run scripts/desktop_automation.py --action capture

# 模拟 Enter 键关闭首次启动/更新遮罩并点击设置页
uv run scripts/desktop_automation.py --action dismiss-and-settings
```

## foliate-js Workflow

If you change anything under `assets/foliate-js/src/`, rebuild `assets/foliate-js/dist/`.

On Windows PowerShell, use:

```powershell
Set-Location assets/foliate-js
& 'E:\nodejs\npm.cmd' ci
if (Test-Path dist) { Remove-Item -Recurse -Force dist }
.\node_modules\.bin\webpack.cmd
```

Notes:
- Do not rely on `npm run build` in native PowerShell. The current script uses `rm -rf dist && webpack`, which is not reliably cross-platform.
- When modifying `foliate-js`, commit only `src/*` files by default. Do not bundle `dist/*` compiled outputs in the same commit as source code changes unless explicitly authorized by the user, ensuring clean commit histories.

## Flutter Dependency And Generated File Hygiene

- Avoid running `fvm flutter pub get` unless needed, especially when `pubspec.yaml` did not change.
- This repo uses git dependencies; `pubspec.lock` can churn unexpectedly. Do not commit lockfile changes unless dependency updates are intentional.
- Platform generated files such as:
  - `linux/flutter/generated_plugins.cmake`
  - `windows/flutter/generated_plugins.cmake`
  - `macos/Flutter/GeneratedPluginRegistrant.swift`
  should only be committed when plugin/dependency changes actually require them.
- Do not commit transient local artifacts such as:
  - `.codex-appdata/`
  - `build/`
  - `android/.kotlin/`

## Reader Bugfix Workflow

This workflow has been validated in this repo and should be preferred for future reader fixes:

1. Reproduce or inspect the bug and identify the actual root cause in Flutter or `foliate-js`.
2. For non-trivial fixes, summarize cause + solution before editing.
3. Implement the smallest safe fix that keeps current behavior stable.
4. If JS renderer code changed, rebuild `assets/foliate-js/dist/`.
5. Let the user manually test reader behavior when the issue depends on real books, layout, pagination, or WebView runtime behavior.
6. Before commit, stage only the relevant source changes and any necessary generated/runtime artifacts.
7. Exclude unrelated dependency churn, build outputs, temp files, and local sample books from the commit.
8. If the user asks for review-first flow, do:
   implement -> user test -> stage relevant files -> subagent/code review -> adjust if needed -> commit
9. Never invoke `git commit` for reader core logic (scrolling, navigation, rendering) until the user has performed manual visual testing and explicitly confirmed the behavior is as expected.

## Known Good Practices From This Repo

- For EPUB renderer issues, prefer fixing the reader instead of mutating user EPUB files.
- For reading-position and pagination bugs, manual verification is often more important than unit coverage alone.
- For layout bugs in the reading UI, favor bounded layouts with graceful truncation over adding new settings or complex behavior.
- When cleaning the workspace, keep user sample books unless explicitly asked to remove them.
- Do not commit design documents or specs (e.g. from brainstorming sessions) into the repository.
- Do not bypass core lifecycle methods (e.g., initialization) to create navigation shortcuts. Always respect the existing state machine.
- Do not use UI hacks (like CSS hiding or `setTimeout`) to mask visual glitches or flashes. Trace the asynchronous loading pipeline to fix the actual state desynchronization.
- Isolate backward compatibility for legacy data formats at the input boundaries. Keep the core engine unaware of deprecated formats, and never backfill legacy data formats into the database silently.
- **GitHub Actions cloud Windows builds must pin `runs-on: windows-2022`**: `windows-latest` floats to Windows Server 2025 (Visual Studio 18 / 2026), which Flutter 3.35.3's CMake generator detection does not recognise and silently falls back to "Visual Studio 16 2019". If VS 2019 is not installed the build fails. Always use `windows-2022` for cloud CI/CD until Flutter explicitly adds VS 18 support.
- **Never add unused Flutter plugins to `dev_dependencies`**: Listing `integration_test: sdk: flutter` (or any other Flutter-bundled plugin) in `dev_dependencies` causes Gradle to emit an import for the plugin's Java class in `GeneratedPluginRegistrant.java`. In a release APK build the plugin is not on the classpath, causing a hard `javac` compile error. Only add a plugin if it is actively used in tests that run in CI.

## Architecture Notes

### State Management

- `Prefs` is a SharedPreferences-backed singleton / notifier for persisted settings.
- Riverpod providers are used for reactive application state.
- Generated files include `*.g.dart`, `*.freezed.dart`, and JSON serialization outputs.

### E-book Rendering

- The reading engine is a Flutter WebView plus `assets/foliate-js/`.
- Dart and JS communicate for navigation, progress, annotations, search, and reading position restore.
- Many reading bugs can involve both Flutter UI and JS renderer state; inspect both sides before deciding on the fix.

### Database

- SQLite schema and migrations are maintained manually in `lib/dao/database.dart`.
- Do not change schema casually; prefer compatibility-preserving fixes unless a migration is clearly required.

## Android Release Packaging

Typical Windows release build:

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

Outputs:
- `build/app/outputs/flutter-apk/app-release.apk`
- `build/app/outputs/bundle/release/app-release.aab` when building app bundles

## Windows Release Packaging (Installer)

This repo uses **Inno Setup 6** to generate a Windows installer (`.exe`) from the Flutter Windows release output.

Prerequisites:
- Install **Inno Setup 6** (needs `ISCC.exe` in PATH or in a known install location).

Build an installer locally (from repo root, PowerShell):

```powershell
# Ensure scripts that invoke bare `flutter` use the FVM-managed project SDK.
$fvmBin = Join-Path $env:LOCALAPPDATA 'Programs\fvm\fvm'
$flutterSdk = (Get-Item -LiteralPath '.fvm\flutter_sdk').Target | Select-Object -First 1
$fvmFlutterBin = Join-Path $flutterSdk 'bin'
$env:Path = "$fvmFlutterBin;$fvmBin;$env:Path"

# Full build (pub get + build windows --release + compile installer)
.\scripts\build_windows_installer.ps1

# If you already have build\windows\x64\runner\Release from a previous build
.\scripts\build_windows_installer.ps1 -SkipBuild
```

Output:
- Installer executable: `build/windows/installer_output/app.exe`

## Windows Desktop CMake Compatibility (VS 2026)

Flutter 3.35.3's cmake generator detection does not include Visual Studio 18 (2026) and
falls back to "Visual Studio 16 2019", which fails if VS 2019 is not installed.

**This machine has VS Build Tools 2026 18.x installed at `E:\Microsoft Visual Studio\18\BuildTools`.**

A one-line patch has been applied to the FVM-managed Flutter SDK to fix this:

File: `E:\FVM\cache\versions\3.35.3\packages\flutter_tools\lib\src\windows\visual_studio.dart`

```dart
// Around line 184 — cmakeGenerator getter
return switch (_majorVersion) {
  17 => 'Visual Studio 17 2022',
  18 => 'Visual Studio 18 2026',  // <-- added
  _ => 'Visual Studio 16 2019',
};
```

Also delete `E:\FVM\cache\versions\3.35.3\bin\cache\flutter_tools.snapshot` and
`flutter_tools.stamp` after applying the patch so the tools are recompiled on next run.

If `fvm install` re-downloads Flutter 3.35.3, the patch must be re-applied.

## GitHub CI/CD Autonomous Verification & Diagnostics (Zero User Supervision)

The AI Agent is fully responsible for verifying CI/CD pass rates autonomously whenever code or release tags are pushed to remote. **Never delegate CI monitoring or log collection to the user.**

### Autonomous Closed-Loop Principle:
1. **Push & Active Monitor**: After `git push`, query the GitHub Actions API to track run progress until completion.
2. **Autonomous Log Extraction**: If a run fails, extract the user's GitHub token via local Git Credential Manager silently, download and unzip the run logs archive via the GitHub API, and grep the exact failure stack trace locally.
3. **Closed-Loop Fix**: Implement root-cause fix -> Run local verification (`fvm flutter test` / `fvm flutter analyze`) -> Push fix -> Re-verify CI until 100% green.

### PowerShell Diagnostic Automation Snippets:

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

