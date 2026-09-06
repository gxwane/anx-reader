#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  file_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "anx_reader/desktop_file_open",
          &flutter::StandardMethodCodec::GetInstance());

  file_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "ready") {
          is_flutter_ready_ = true;
          for (const auto& file : pending_files_) {
            file_channel_->InvokeMethod(
                "onOpenFile",
                std::make_unique<flutter::EncodableValue>(file));
          }
          pending_files_.clear();
          result->Success(flutter::EncodableValue(true));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (file_channel_) {
    file_channel_ = nullptr;
  }

  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      if (message == WM_SIZE || message == WM_ACTIVATE) {
        Win32Window::MessageHandler(hwnd, message, wparam, lparam);
      }
      return *result;
    }
  }

  switch (message) {
    case WM_COPYDATA: {
      auto cds = reinterpret_cast<PCOPYDATASTRUCT>(lparam);
      if (cds != nullptr && cds->dwData == 0x414E58 && cds->lpData != nullptr &&
          cds->cbData > 0) {
        std::string file_path(reinterpret_cast<const char*>(cds->lpData),
                              cds->cbData);
        while (!file_path.empty() && file_path.back() == '\0') {
          file_path.pop_back();
        }
        if (!file_path.empty()) {
          if (is_flutter_ready_ && file_channel_) {
            file_channel_->InvokeMethod(
                "onOpenFile",
                std::make_unique<flutter::EncodableValue>(file_path));
          } else {
            pending_files_.push_back(file_path);
          }
        }
        return TRUE;
      }
      break;
    }
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
