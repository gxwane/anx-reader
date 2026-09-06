import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var fileChannel: FlutterMethodChannel?
  private var pendingFiles: [String] = []
  private var isFlutterReady: Bool = false

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let controller = mainFlutterWindow?.contentViewController as! FlutterViewController
    fileChannel = FlutterMethodChannel(
      name: "anx_reader/desktop_file_open",
      binaryMessenger: controller.engine.binaryMessenger
    )

    fileChannel?.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else { return }
      if call.method == "ready" {
        self.isFlutterReady = true
        for file in self.pendingFiles {
          self.fileChannel?.invokeMethod("onOpenFile", arguments: file)
        }
        self.pendingFiles.removeAll()
        result(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.applicationDidFinishLaunching(notification)
  }

  override func application(_ sender: NSApplication, openFiles filenames: [String]) {
    if isFlutterReady, let channel = fileChannel {
      for file in filenames {
        channel.invokeMethod("onOpenFile", arguments: file)
      }
    } else {
      pendingFiles.append(contentsOf: filenames)
    }
    sender.reply(toOpenOrPrint: .success)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
