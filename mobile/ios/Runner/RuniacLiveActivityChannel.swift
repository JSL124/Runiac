import Flutter
import UIKit

final class RuniacLiveActivityChannel {
  private static let channelName = "runiac/run_live_activity"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard #available(iOS 16.1, *) else {
        result(nil)
        return
      }

      switch call.method {
      case "start":
        guard let payload = RuniacLiveActivityPayload(arguments: call.arguments) else {
          result(FlutterError(code: "invalid_payload", message: "Invalid Live Activity payload.", details: nil))
          return
        }
        Task { @MainActor in
          do {
            try await RuniacLiveActivityManager.shared.start(payload: payload)
            result(nil)
          } catch {
            result(FlutterError(code: "start_failed", message: error.localizedDescription, details: nil))
          }
        }
      case "update":
        guard let payload = RuniacLiveActivityPayload(arguments: call.arguments) else {
          result(FlutterError(code: "invalid_payload", message: "Invalid Live Activity payload.", details: nil))
          return
        }
        Task { @MainActor in
          await RuniacLiveActivityManager.shared.update(payload: payload)
          result(nil)
        }
      case "stop":
        Task { @MainActor in
          await RuniacLiveActivityManager.shared.stop()
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

struct RuniacLiveActivityPayload {
  let title: String
  let statusLabel: String
  let elapsedTimeLabel: String
  let averagePaceLabel: String
  let distanceLabel: String
  let supportCopy: String

  init?(arguments: Any?) {
    guard let arguments = arguments as? [String: Any],
          let title = arguments["title"] as? String,
          let statusLabel = arguments["statusLabel"] as? String,
          let elapsedTimeLabel = arguments["elapsedTimeLabel"] as? String,
          let averagePaceLabel = arguments["averagePaceLabel"] as? String,
          let distanceLabel = arguments["distanceLabel"] as? String
    else {
      return nil
    }

    self.title = title
    self.statusLabel = statusLabel
    self.elapsedTimeLabel = elapsedTimeLabel
    self.averagePaceLabel = averagePaceLabel
    self.distanceLabel = distanceLabel
    self.supportCopy = arguments["supportCopy"] as? String ?? ""
  }
}
