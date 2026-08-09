import Flutter
import UIKit

/// Shares a rendered rank card into Instagram Stories as a sticker via the
/// documented `instagram-stories://share` deep link. The image is placed on the
/// system pasteboard under Instagram's sticker keys; Instagram reads it after
/// the deep link opens. Requires `instagram-stories` in
/// `LSApplicationQueriesSchemes` and a valid Facebook App ID as
/// `source_application`.
final class RuniacInstagramStoryChannel {
  private static let channelName = "runiac/instagram_story"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    let handler = RuniacInstagramStoryChannel()
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        handler.isAvailable(result: result)
      case "shareSticker":
        handler.shareSticker(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func isAvailable(result: @escaping FlutterResult) {
    guard let url = URL(string: "instagram-stories://share") else {
      result(false)
      return
    }
    result(UIApplication.shared.canOpenURL(url))
  }

  private func shareSticker(arguments: Any?, result: @escaping FlutterResult) {
    guard
      let args = arguments as? [String: Any],
      let imageData = (args["stickerImage"] as? FlutterStandardTypedData)?.data,
      let appId = args["appId"] as? String,
      !appId.isEmpty
    else {
      result(FlutterError(
        code: "bad_args",
        message: "Missing sticker image or Facebook App ID",
        details: nil
      ))
      return
    }

    guard
      let shareURL = URL(string: "instagram-stories://share?source_application=\(appId)"),
      UIApplication.shared.canOpenURL(shareURL)
    else {
      result(false)
      return
    }

    let topColor = (args["backgroundTopColor"] as? String) ?? "#0B1B3A"
    let bottomColor = (args["backgroundBottomColor"] as? String) ?? "#2F50C7"

    let pasteboardItems: [String: Any] = [
      "com.instagram.sharedSticker.stickerImage": imageData,
      "com.instagram.sharedSticker.backgroundTopColor": topColor,
      "com.instagram.sharedSticker.backgroundBottomColor": bottomColor,
    ]
    let options: [UIPasteboard.OptionsKey: Any] = [
      .expirationDate: Date().addingTimeInterval(60 * 5)
    ]

    DispatchQueue.main.async {
      UIPasteboard.general.setItems([pasteboardItems], options: options)
      UIApplication.shared.open(shareURL, options: [:]) { success in
        result(success)
      }
    }
  }
}
