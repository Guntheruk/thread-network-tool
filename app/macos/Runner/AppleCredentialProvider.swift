import Foundation
import FlutterMacOS
import Security
import ThreadNetwork

/// Read-only bridge. Registration does not instantiate THClient or request access.
enum AppleCredentialProvider {
  private static let entitlement =
    "com.apple.developer.networking.manage-thread-network-credentials"

  private final class PendingFetch {
    let id: Int
    let client: THClient
    var result: FlutterResult?
    var cancelled = false

    init(id: Int, client: THClient, result: @escaping FlutterResult) {
      self.id = id
      self.client = client
      self.result = result
    }
  }

  // Accessed only on the main queue. A cancelled Apple prompt still owns the
  // slot until its callback arrives, so a retry cannot start a second prompt.
  private static var pendingFetch: PendingFetch?

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "thread_network/apple_credentials",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "availability":
        availability(result)
      case "fetchPreferred":
        fetchPreferred(call.arguments, result)
      case "cancelFetch":
        cancelFetch(call.arguments, result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func status(_ value: String, _ result: @escaping FlutterResult) {
    DispatchQueue.main.async { result(["status": value]) }
  }

  private static func isAccessConfigured() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    return SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) as? Bool == true
  }

  private static func client(for selector: String, _ result: @escaping FlutterResult) -> THClient? {
    guard #available(macOS 13.0, *) else {
      status("unavailable", result)
      return nil
    }
    guard isAccessConfigured() else {
      status("accessNotConfigured", result)
      return nil
    }
    guard NSClassFromString("THClient") != nil else {
      status("unavailable", result)
      return nil
    }
    let client = THClient()
    guard client.responds(to: NSSelectorFromString(selector)) else {
      status("unavailable", result)
      return nil
    }
    return client
  }

  private static func availability(_ result: @escaping FlutterResult) {
    guard let client = client(
      for: "isPreferredNetworkAvailableWithCompletion:", result) else { return }
    client.isPreferredNetworkAvailable { available in
      status(available ? "available" : "noCredentials", result)
    }
  }

  private static func fetchPreferred(_ arguments: Any?, _ result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let args = arguments as? [String: Any],
            let requestID = args["requestId"] as? Int else {
        result(["status": "failure"])
        return
      }
      guard pendingFetch == nil else {
        result(["status": "inProgress"])
        return
      }
      guard let client = client(for: "retrievePreferredCredentials:", result) else { return }
      let request = PendingFetch(id: requestID, client: client, result: result)
      pendingFetch = request
      client.retrievePreferredCredentials { credentials, error in
        DispatchQueue.main.async {
          guard pendingFetch === request else { return }
          pendingFetch = nil
          guard !request.cancelled, let reply = request.result else { return }
          request.result = nil
          if let error = error {
            // Code 15 alone is ambiguous across NSError domains.
            let nsError = error as NSError
            let denied = nsError.domain == "ThreadCredentialsStore" && nsError.code == 15
            reply(["status": denied ? "permissionDenied" : "failure"])
            return
          }
          guard let dataset = credentials?.activeOperationalDataSet, !dataset.isEmpty,
                dataset.count <= 254 else {
            reply(["status": credentials == nil ? "noCredentials" : "failure"])
            return
          }
          reply([
            "status": "available",
            "dataset": FlutterStandardTypedData(bytes: dataset)
          ])
        }
      }
    }
  }

  private static func cancelFetch(_ arguments: Any?, _ result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      if let args = arguments as? [String: Any],
         let requestID = args["requestId"] as? Int,
         let request = pendingFetch, request.id == requestID {
        request.cancelled = true
        request.result?(["status": "cancelled"])
        request.result = nil
      }
      result(nil)
    }
  }
}
