import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    AppleCredentialProvider.register(with: flutterViewController)
    let moveStorage = FlutterMethodChannel(
      name: "thread_network_tool/move_storage",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    moveStorage.setMethodCallHandler { call, result in
      guard call.method == "privateDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }
      do {
        let support = try FileManager.default.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true)
        let directory = support.appendingPathComponent("ThreadNetworkToolMove", isDirectory: true)
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true,
          attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue == 0o700 else {
          result(FlutterError(code: "storage_unavailable", message: nil, details: nil))
          return
        }
        result(directory.path)
      } catch {
        result(FlutterError(code: "storage_unavailable", message: nil, details: nil))
      }
    }

    super.awakeFromNib()
  }
}
