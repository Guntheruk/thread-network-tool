import Flutter
import Foundation
import ThreadNetwork

/// Registration and availability never request credential consent.
enum AppleCredentialProvider {
  private static let gate = AppleCredentialRequestGate()

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "thread_network/apple_credentials", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      DispatchQueue.main.async {
        switch call.method {
        case "availability": availability(result)
        case "fetchPreferred": fetchPreferred(call.arguments, result)
        case "cancelFetch":
          if let args = call.arguments as? [String: Any], let id = args["requestId"] as? Int {
            gate.cancel(id: id)
          }
          result(nil)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  private static func client(_ result: @escaping FlutterResult) -> THClient? {
    guard #available(iOS 16.4, *) else {
      result(["status": "unavailable"])
      return nil
    }
    // iOS has no public SecTask entitlement preflight. The developer opts in
    // only after configuring the matching profile; the OS still enforces it.
    #if THREAD_CREDENTIALS_ENABLED && !targetEnvironment(simulator)
    return THClient()
    #else
    result(["status": "accessNotConfigured"])
    return nil
    #endif
  }

  private static func availability(_ result: @escaping FlutterResult) {
    guard let client = client(result) else { return }
    guard #available(iOS 16.4, *) else { return }
    var reply: FlutterResult? = result
    let deadline = DispatchWorkItem {
      reply?(["status": "timedOut"])
      reply = nil
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: deadline)
    client.isPreferredNetworkAvailable { available in
      DispatchQueue.main.async {
        deadline.cancel()
        reply?(["status": available ? "available" : "noCredentials"])
        reply = nil
      }
    }
  }

  private static func fetchPreferred(_ arguments: Any?, _ result: @escaping FlutterResult) {
    guard let args = arguments as? [String: Any], let id = args["requestId"] as? Int else {
      result(["status": "failure"])
      return
    }
    guard let client = client(result) else { return }
    guard let request = gate.start(id: id, client: client, timeout: 60,
                                   reply: { result($0) }) else {
      result(["status": "inProgress"])
      return
    }
    // This is the only credential API call, reached by explicit UI action.
    client.retrievePreferredCredentials { credentials, error in
      DispatchQueue.main.async {
        let response: [String: Any]
        if let error = error as NSError? {
          let denied = error.domain == "ThreadCredentialsStore" && error.code == 15
          response = ["status": denied ? "permissionDenied" : "failure"]
        } else if let dataset = credentials?.activeOperationalDataSet,
                  !dataset.isEmpty, dataset.count <= 254 {
          response = ["status": "available", "dataset": FlutterStandardTypedData(bytes: dataset)]
        } else {
          response = ["status": credentials == nil ? "noCredentials" : "failure"]
        }
        gate.complete(request, response: response)
      }
    }
  }
}
