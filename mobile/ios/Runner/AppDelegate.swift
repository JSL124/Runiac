import Flutter
import GoogleSignIn
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ application: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    if GIDSignIn.sharedInstance.handle(url) {
      return true
    }

    return super.application(application, open: url, options: options)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "RuniacLiveActivityChannel"
    ) else { return }
    RuniacLiveActivityChannel.register(with: registrar.messenger())
    RuniacPhoneMotionCadenceChannel.register(with: registrar.messenger())
    RuniacPlanNotificationChannel.register(with: registrar.messenger())
    RuniacInstagramStoryChannel.register(with: registrar.messenger())
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    NSLog(
      "[RuniacLocalNotifications][iOS] willPresent id=\(notification.request.identifier)"
    )
    RuniacPlanNotificationChannel.recordDelivery(
      identifier: notification.request.identifier,
      at: notification.date
    )
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .list, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    NSLog(
      "[RuniacLocalNotifications][iOS] didReceive id=\(response.notification.request.identifier)"
    )
    RuniacPlanNotificationChannel.recordDelivery(
      identifier: response.notification.request.identifier,
      at: response.notification.date
    )
    completionHandler()
  }
}
