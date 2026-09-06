#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <shlobj.h>
#include <windows.h>

#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

constexpr const wchar_t kSingleInstanceMutexName[] =
    L"Local\\AnxReaderGXPreviewSingleInstanceMutex";
constexpr const wchar_t kAnxWindowPropName[] =
    L"AnxReader_GX_Window";
constexpr DWORD kAnxCopyDataMagic = 0x414E58;  // 'ANX'

struct FindExistingWindowData {
  HWND found_hwnd = nullptr;
};

BOOL CALLBACK EnumWindowsCallback(HWND hwnd, LPARAM lParam) {
  auto* data = reinterpret_cast<FindExistingWindowData*>(lParam);
  if (::GetProp(hwnd, kAnxWindowPropName) != nullptr) {
    data->found_hwnd = hwnd;
    return FALSE;  // Stop enumerating
  }
  return TRUE;
}

HWND FindExistingAnxWindow() {
  FindExistingWindowData data;
  ::EnumWindows(EnumWindowsCallback, reinterpret_cast<LPARAM>(&data));
  return data.found_hwnd;
}

void RegisterWindowsFileAssociations() {
  wchar_t exe_path[MAX_PATH];
  if (::GetModuleFileName(nullptr, exe_path, MAX_PATH) == 0) {
    return;
  }

  std::wstring exe_str(exe_path);
  size_t last_slash = exe_str.find_last_of(L"\\/");
  std::wstring exe_name = (last_slash != std::wstring::npos)
                              ? exe_str.substr(last_slash + 1)
                              : L"anx_reader_gx_preview.exe";

  const wchar_t* extensions[] = {
      L".epub", L".mobi", L".azw3", L".azw", L".fb2", L".txt", L".pdf"};

  // 1. HKCU\Software\Classes\AnxReader.BookFile
  HKEY prog_key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\AnxReader.BookFile",
                        0, nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                        &prog_key, nullptr) == ERROR_SUCCESS) {
    const wchar_t desc[] = L"eBook Document";
    ::RegSetValueExW(prog_key, nullptr, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(desc),
                     static_cast<DWORD>((wcslen(desc) + 1) * sizeof(wchar_t)));
    ::RegCloseKey(prog_key);
  }

  // 2. HKCU\Software\Classes\AnxReader.BookFile\DefaultIcon
  HKEY icon_key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER,
                        L"Software\\Classes\\AnxReader.BookFile\\DefaultIcon", 0,
                        nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                        &icon_key, nullptr) == ERROR_SUCCESS) {
    std::wstring icon_val = L"\"" + exe_str + L"\",0";
    ::RegSetValueExW(icon_key, nullptr, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(icon_val.c_str()),
                     static_cast<DWORD>((icon_val.length() + 1) * sizeof(wchar_t)));
    ::RegCloseKey(icon_key);
  }

  // 3. HKCU\Software\Classes\AnxReader.BookFile\shell\open\command
  HKEY cmd_key = nullptr;
  if (::RegCreateKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Classes\\AnxReader.BookFile\\shell\\open\\command", 0,
          nullptr, REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &cmd_key,
          nullptr) == ERROR_SUCCESS) {
    std::wstring cmd_val = L"\"" + exe_str + L"\" \"%1\"";
    ::RegSetValueExW(cmd_key, nullptr, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(cmd_val.c_str()),
                     static_cast<DWORD>((cmd_val.length() + 1) * sizeof(wchar_t)));
    ::RegCloseKey(cmd_key);
  }

  // 4. HKCU\Software\Classes\Applications\<exe_name>
  std::wstring app_sub = L"Software\\Classes\\Applications\\" + exe_name;
  HKEY app_key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, app_sub.c_str(), 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &app_key,
                        nullptr) == ERROR_SUCCESS) {
    const wchar_t friendly[] = L"Anx Reader GX Preview";
    ::RegSetValueExW(app_key, L"FriendlyAppName", 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(friendly),
                     static_cast<DWORD>((wcslen(friendly) + 1) * sizeof(wchar_t)));
    ::RegCloseKey(app_key);
  }

  std::wstring app_cmd_sub = app_sub + L"\\shell\\open\\command";
  HKEY app_cmd_key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, app_cmd_sub.c_str(), 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                        &app_cmd_key, nullptr) == ERROR_SUCCESS) {
    std::wstring cmd_val = L"\"" + exe_str + L"\" \"%1\"";
    ::RegSetValueExW(app_cmd_key, nullptr, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(cmd_val.c_str()),
                     static_cast<DWORD>((cmd_val.length() + 1) * sizeof(wchar_t)));
    ::RegCloseKey(app_cmd_key);
  }

  std::wstring supp_sub = app_sub + L"\\SupportedTypes";
  HKEY supp_key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, supp_sub.c_str(), 0, nullptr,
                        REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &supp_key,
                        nullptr) == ERROR_SUCCESS) {
    const wchar_t empty[] = L"";
    for (const auto* ext : extensions) {
      ::RegSetValueExW(supp_key, ext, 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(empty), sizeof(wchar_t));
    }
    ::RegCloseKey(supp_key);
  }

  // 5. HKCU\Software\Classes\<ext>\OpenWithProgids
  for (const auto* ext : extensions) {
    std::wstring ext_sub = std::wstring(L"Software\\Classes\\") + ext +
                           L"\\OpenWithProgids";
    HKEY ext_key = nullptr;
    if (::RegCreateKeyExW(HKEY_CURRENT_USER, ext_sub.c_str(), 0, nullptr,
                          REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &ext_key,
                          nullptr) == ERROR_SUCCESS) {
      const wchar_t empty[] = L"";
      ::RegSetValueExW(ext_key, L"AnxReader.BookFile", 0, REG_SZ,
                       reinterpret_cast<const BYTE*>(empty), sizeof(wchar_t));
      ::RegCloseKey(ext_key);
    }
  }

  ::SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST, nullptr, nullptr);
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Register file associations in HKCU so the app appears in Windows "Open with"
  // (打开方式) regardless of installer or portable execution.
  RegisterWindowsFileAssociations();

  // Single-instance check and IPC file dispatch
  HANDLE single_instance_mutex =
      ::CreateMutex(nullptr, TRUE, kSingleInstanceMutexName);
  if (single_instance_mutex != nullptr &&
      ::GetLastError() == ERROR_ALREADY_EXISTS) {
    HWND existing_window = FindExistingAnxWindow();
    // Bounded retry up to 1.5 seconds (15 x 100ms) while primary instance is creating window
    for (int retries = 0; retries < 15 && existing_window == nullptr; ++retries) {
      ::Sleep(100);
      existing_window = FindExistingAnxWindow();
    }

    if (existing_window != nullptr) {
      std::vector<std::string> args = GetCommandLineArguments();
      if (!args.empty()) {
        const std::string& file_path = args[0];
        COPYDATASTRUCT cds;
        cds.dwData = kAnxCopyDataMagic;
        cds.cbData = static_cast<DWORD>(file_path.size() + 1);
        cds.lpData = const_cast<char*>(file_path.c_str());

        DWORD_PTR result = 0;
        ::SendMessageTimeout(existing_window, WM_COPYDATA, 0,
                             reinterpret_cast<LPARAM>(&cds),
                             SMTO_ABORTIFHUNG | SMTO_BLOCK, 2000, &result);
      }

      DWORD target_pid = 0;
      ::GetWindowThreadProcessId(existing_window, &target_pid);
      if (target_pid != 0) {
        ::AllowSetForegroundWindow(target_pid);
      }

      if (::IsIconic(existing_window)) {
        ::ShowWindow(existing_window, SW_RESTORE);
      }
      ::SetForegroundWindow(existing_window);
    }

    ::CloseHandle(single_instance_mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Anx Reader GX Preview", origin, size)) {
    if (single_instance_mutex != nullptr) {
      ::CloseHandle(single_instance_mutex);
    }
    ::CoUninitialize();
    return EXIT_FAILURE;
  }
  ::SetProp(window.GetHandle(), kAnxWindowPropName, reinterpret_cast<HANDLE>(1));
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::RemoveProp(window.GetHandle(), kAnxWindowPropName);
  if (single_instance_mutex != nullptr) {
    ::CloseHandle(single_instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
