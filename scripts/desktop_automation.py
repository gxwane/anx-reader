# /// script
# dependencies = [
#     "pywinauto",
#     "pyautogui",
#     "pillow",
#     "pywin32",
# ]
# ///

"""
Windows Desktop Automation Script for Anx Reader GX Preview.
Usage:
    uv run scripts/desktop_automation.py --action capture
    uv run scripts/desktop_automation.py --action dismiss
    uv run scripts/desktop_automation.py --action dismiss-and-settings
"""

import argparse
import os
import sys
import time
from pathlib import Path
from PIL import ImageGrab

try:
    import pyautogui
    from pywinauto import Application, Desktop
except ImportError:
    pass


import ctypes
import win32con
import win32gui
import win32ui
from PIL import Image


def find_anx_hwnd():
    """Find the HWND of the running Anx Reader window."""
    found_hwnds = []

    def enum_cb(hwnd, extra):
        if win32gui.IsWindowVisible(hwnd):
            title = win32gui.GetWindowText(hwnd)
            if "Anx Reader" in title or "anx_reader" in title:
                found_hwnds.append((hwnd, title))
        return True

    win32gui.EnumWindows(enum_cb, None)
    if found_hwnds:
        return found_hwnds[0][0]
    return None


def capture_window(out_path: str):
    """Capture screenshot of the running window via Win32 PrintWindow."""
    out = Path(out_path).resolve()
    out.parent.mkdir(parents=True, exist_ok=True)

    hwnd = find_anx_hwnd()
    if not hwnd:
        print("[WARN] Anx Reader window HWND not found. Checking running processes...")
        # Fallback to desktop screen grab
        try:
            img = ImageGrab.grab()
            img.save(str(out))
            print(f"[SUCCESS] Desktop screen captured -> {out}")
            return True
        except Exception as e:
            print(f"[ERROR] Screen grab failed: {e}")
            return False

    try:
        left, top, right, bottom = win32gui.GetWindowRect(hwnd)
        w = max(right - left, 100)
        h = max(bottom - top, 100)

        hwnd_dc = win32gui.GetWindowDC(hwnd)
        mfc_dc = win32ui.CreateDCFromHandle(hwnd_dc)
        save_dc = mfc_dc.CreateCompatibleDC()
        save_bmp = win32ui.CreateBitmap()
        save_bmp.CreateCompatibleBitmap(mfc_dc, w, h)
        save_dc.SelectObject(save_bmp)

        # PW_RENDERFULLCONTENT = 2
        ctypes.windll.user32.PrintWindow(hwnd, save_dc.GetSafeHdc(), 2)

        bmp_info = save_bmp.GetInfo()
        bmp_str = save_bmp.GetBitmapBits(True)
        img = Image.frombuffer(
            "RGB",
            (bmp_info["bmWidth"], bmp_info["bmHeight"]),
            bmp_str,
            "raw",
            "BGRX",
            0,
            1,
        )
        img.save(str(out))
        print(f"[SUCCESS] Captured window (HWND {hwnd}, {w}x{h}) -> {out}")

        win32gui.DeleteObject(save_bmp.GetHandle())
        save_dc.DeleteDC()
        mfc_dc.DeleteDC()
        win32gui.ReleaseDC(hwnd, hwnd_dc)
        return True
    except Exception as e:
        print(f"[ERROR] PrintWindow capture failed: {e}")
        return False


def dismiss_modal():
    """Bring window to foreground and send Enter to dismiss any modal/changelog overlay."""
    win = find_anx_window()
    if win:
        win.set_focus()
        time.sleep(0.3)
    pyautogui.press("enter")
    time.sleep(0.5)
    print("[SUCCESS] Sent Enter key to dismiss modal")


def click_settings():
    """Click on the settings navigation tab."""
    win = find_anx_window()
    if not win:
        print("[ERROR] Anx Reader window not found")
        return False

    win.set_focus()
    time.sleep(0.3)
    rect = win.rectangle()

    # In desktop layout (NavigationRail on the left), the settings icon is typically
    # at the bottom of the left rail: left ~40px, bottom ~40px from window bottom.
    click_x = rect.left + 40
    click_y = rect.bottom - 40
    pyautogui.click(click_x, click_y)
    time.sleep(0.5)
    print(f"[SUCCESS] Clicked settings navigation at ({click_x}, {click_y})")
    return True


def main():
    parser = argparse.ArgumentParser(description="Anx Reader Windows Automation CLI")
    parser.add_argument(
        "--action",
        choices=["capture", "dismiss", "settings", "dismiss-and-settings"],
        default="capture",
        help="Action to perform",
    )
    parser.add_argument(
        "--out",
        default="C:/Users/wgx/.gemini/antigravity-cli/brain/83905166-261b-4d52-b76b-38b40e69b0e5/scratch/desktop_live_capture.png",
        help="Output path for screenshots",
    )
    args = parser.parse_args()

    if args.action == "capture":
        capture_window(args.out)
    elif args.action == "dismiss":
        dismiss_modal()
        capture_window(args.out)
    elif args.action == "settings":
        click_settings()
        capture_window(args.out)
    elif args.action == "dismiss-and-settings":
        dismiss_modal()
        time.sleep(0.5)
        click_settings()
        time.sleep(0.5)
        capture_window(args.out)


if __name__ == "__main__":
    main()
