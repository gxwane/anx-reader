# Mobile Autonomous AI Testing & ADB Verification SOP

This runbook specifies the autonomous mobile verification protocol for Anx Reader using the official Android SDK Emulator and ADB automation.

---

## 1. Architectural Principles & Agent Autonomy

- **Agent Closed-Loop Autonomy**: For issues involving mobile background lifecycles (screen sleep/wake, process suspension, background audio, chapter boundaries, and WebDAV sync), AI agents must autonomously verify behavior on the emulator before requesting human verification.
- **Zero-Hallucination Inspection**: Every assertion must be proven by concrete OS telemetry:
  - System service dumps (`dumpsys media_session`, `dumpsys power`).
  - Screen hierarchy inspection (`uiautomator dump`).
  - Pixel-level verification via captured screenshots.

---

## 2. Build & Deploy Contract (x86_64 ABI Requirement)

When building and testing on the official `x86_64` Google APIs emulator, **the target platform must be explicitly passed**:

```powershell
# Mandatory: Build debug APK with x86_64 ABI
fvm flutter build apk --debug --target-platform android-x64

# Install to emulator
adb -s emulator-5554 install -r build/app/outputs/flutter-apk/app-debug.apk

# Launch main activity
adb -s emulator-5554 shell am start -n io.github.gxwane.anx_reader_gx_preview/com.anxcye.anx_reader.MainActivity
```

> [!WARNING]
> Running `fvm flutter build apk --debug` without `--target-platform android-x64` defaults to compiling only ARM ABIs (`armeabi-v7a`, `arm64-v8a`). Running an ARM-only APK on an `x86_64` Google APIs emulator causes an immediate crash with `java.lang.UnsatisfiedLinkError: dlopen failed: ... libflutter.so has unexpected e_machine: 183`.

---

## 3. Telemetry & Inspection Protocols

### A. Screen Hierarchy Dump (uiautomator)
Inspect the active screen to find exact element bounding boxes `[x1,y1][x2,y2]`:

```powershell
adb -s emulator-5554 shell uiautomator dump /sdcard/dump.xml
adb -s emulator-5554 shell cat /sdcard/dump.xml
```

### B. Binary-Safe Screenshot Capture
Never redirect `adb exec-out screencap -p > file.png` directly inside PowerShell/pwsh, as PowerShell converts binary data to UTF-16LE / CRLF text, corrupting the PNG header.

Use one of these two binary-safe patterns:

```powershell
# Pattern A: Device staging + ADB pull (100% reliable across all shells)
adb -s emulator-5554 shell screencap -p /sdcard/cap.png
adb -s emulator-5554 pull /sdcard/cap.png .\cap.png
adb -s emulator-5554 shell rm /sdcard/cap.png

# Pattern B: cmd.exe bypass (avoids pwsh stream transcoding)
cmd.exe /c "adb -s emulator-5554 exec-out screencap -p > cap.png"
```

---

## 4. Mobile Lifecycle & Hardware Emulation Recipes

### A. Screen Sleep & Lock Simulation
```powershell
# Press POWER button to turn screen off
adb -s emulator-5554 shell input keyevent 26

# Verify device entered sleep state
adb -s emulator-5554 shell dumpsys power | grep "mWakefulness="
# Expected: mWakefulness=Asleep or Dozing
```

### B. Screen Wakeup & Unlock
```powershell
# Turn screen back on (WAKEUP)
adb -s emulator-5554 shell input keyevent 224

# Dismiss lockscreen / keyguard (MENU key)
adb -s emulator-5554 shell input keyevent 82

# Alternative: swipe up to unlock if keyguard requires swipe
adb -s emulator-5554 shell input swipe 160 500 160 100 200
```

### C. Audio & MediaSession Verification
Used to inspect background TTS, audio playback state, and lockscreen metadata without turning on the screen:

```powershell
# Check playback state and metadata
adb -s emulator-5554 shell dumpsys media_session | grep -A 10 "package=io.github.gxwane.anx_reader_gx_preview"

# Expected state values:
# state=PLAYING(3) -> Currently playing
# state=PAUSED(2)  -> Paused
# state=STOPPED(1) -> Stopped
```

> [!CAUTION]
> When testing audio, TTS, or background playback, **NEVER pass `-no-audio`** to the emulator startup arguments. Disabling the emulator audio HAL stops the hardware playback clock, causing background audio threads to deadlock or hang indefinitely.

### D. Touch & Gesture Automation
```powershell
# Tap specific coordinates:
adb -s emulator-5554 shell input tap <x> <y>

# Page navigation shortcuts (e.g. 320x640 screen):
adb -s emulator-5554 shell input tap 280 320   # Next page (right edge)
adb -s emulator-5554 shell input tap 40 320    # Previous page (left edge)
adb -s emulator-5554 shell input tap 160 320   # Center menu toggle

# Media control keys:
adb -s emulator-5554 shell input keyevent 85   # MEDIA_PLAY_PAUSE
adb -s emulator-5554 shell input keyevent 87   # MEDIA_NEXT
adb -s emulator-5554 shell input keyevent 88   # MEDIA_PREVIOUS
```

---

## 5. End-to-End Verification Pattern: Background Lifecycle & Viewport Self-Healing

1. **Setup**: Boot emulator, install APK (`android-x64`), push test book to `/sdcard/Download/`.
2. **Launch & Open**: Open reader, navigate past introductory chapters to continuous prose text.
3. **Trigger Playback**: Start TTS, assert `dumpsys media_session` shows `state=PLAYING(3)`.
4. **Assert Initial Highlight**: Take screenshot and assert active sentence is highlighted.
5. **Simulate Sleep**: Send `keyevent 26`, assert `mWakefulness=Asleep`.
6. **Background Passage**: Allow audio to play across sentence and chapter boundaries while asleep.
7. **Simulate Wakeup**: Send `keyevent 224 && keyevent 82`.
8. **Assert Viewport Self-Healing**: Take screenshot immediately upon waking, verify reader viewport snapped to the currently playing sentence and highlight is active.
