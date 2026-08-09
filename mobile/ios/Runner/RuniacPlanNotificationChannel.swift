import Flutter
import Foundation
import UserNotifications

final class RuniacPlanNotificationChannel {
  private static let channelName = "runiac/plan_notifications"
  private static let scheduledIdsKey = "runiac.planNotificationIds"
  private static let deliveriesKey = "runiac.planNotificationDeliveries"
  private static let maxDeliveryRecords = 200
  private static var channel: FlutterMethodChannel?

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    Self.channel = channel
    let scheduler = RuniacPlanNotificationChannel()
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "requestPermission":
        scheduler.requestPermission(arguments: call.arguments, result: result)
      case "syncPlanNotifications":
        scheduler.syncPlanNotifications(arguments: call.arguments, result: result)
      case "schedulePlanNotification":
        scheduler.schedulePlanNotification(arguments: call.arguments, result: result)
      case "cancelPlanNotifications":
        scheduler.cancelPlanNotifications()
        result(nil)
      case "consumeDeliveredNotifications":
        scheduler.consumeDeliveredNotifications(arguments: call.arguments, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Records that the system presented a notification, from the app delegate's
  /// `willPresent` (foreground) and `didReceive` (tap) callbacks.
  ///
  /// Neither callback fires for a notification that was delivered in the
  /// background and never tapped, which is why
  /// `consumeDeliveredNotifications` also sweeps
  /// `getDeliveredNotifications()`, and why Dart keeps a time-based backstop
  /// on top of both.
  static func recordDelivery(identifier: String, at date: Date) {
    guard !identifier.isEmpty else {
      return
    }
    var records = storedDeliveries()
    records.append([
      "id": identifier,
      "deliveredAtMillis": NSNumber(value: Int64(date.timeIntervalSince1970 * 1000)),
    ])
    if records.count > maxDeliveryRecords {
      records.removeFirst(records.count - maxDeliveryRecords)
    }
    UserDefaults.standard.set(records, forKey: deliveriesKey)
    channel?.invokeMethod("onPlanNotificationDelivered", arguments: nil)
  }

  private static func storedDeliveries() -> [[String: Any]] {
    UserDefaults.standard.array(forKey: deliveriesKey) as? [[String: Any]] ?? []
  }

  /// Returns every delivery this device recorded and clears the stored ones.
  ///
  /// Identifiers are reported unfiltered; Dart matches them against its own
  /// ledger, so a push notification's identifier is simply ignored there. The
  /// notification centre sweep deliberately does not clear the tray, and
  /// re-reporting an already-materialized identifier is harmless because its
  /// ledger entry is gone by then.
  private func consumeDeliveredNotifications(arguments: Any?, result: @escaping FlutterResult) {
    let debugLogs = debugLogsEnabled(arguments)
    let stored = Self.storedDeliveries()
    UserDefaults.standard.removeObject(forKey: Self.deliveriesKey)

    UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
      var merged = stored
      var seen = Set(stored.compactMap { $0["id"] as? String })
      for notification in notifications {
        let identifier = notification.request.identifier
        guard !identifier.isEmpty, !seen.contains(identifier) else {
          continue
        }
        seen.insert(identifier)
        merged.append([
          "id": identifier,
          "deliveredAtMillis": NSNumber(
            value: Int64(notification.date.timeIntervalSince1970 * 1000)
          ),
        ])
      }
      self.log("consumeDeliveredNotifications count=\(merged.count)", enabled: debugLogs)
      DispatchQueue.main.async {
        result(merged)
      }
    }
  }

  private func requestPermission(arguments: Any?, result: @escaping FlutterResult) {
    let debugLogs = debugLogsEnabled(arguments)
    log("requestPermission requested", enabled: debugLogs)
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) {
      granted, error in
      DispatchQueue.main.async {
        if let error = error {
          self.log("requestPermission error=\(error.localizedDescription)", enabled: debugLogs)
        }
        self.log("requestPermission granted=\(granted)", enabled: debugLogs)
        result(granted ? "granted" : "denied")
      }
    }
  }

  private func syncPlanNotifications(arguments: Any?, result: @escaping FlutterResult) {
    let notifications = notificationsFromArguments(arguments)
    let debugLogs = debugLogsEnabled(arguments)
    log("syncPlanNotifications parsedCount=\(notifications.count)", enabled: debugLogs)
    cancelPlanNotifications()
    saveScheduledIds(notifications.map(\.id))
    let center = UNUserNotificationCenter.current()
    for notification in notifications where notification.scheduledAt > Date() {
      add(notification, center: center, debugLogs: debugLogs)
    }
    logPendingRequests(context: "syncPlanNotifications", enabled: debugLogs)
    result(nil)
  }

  private func schedulePlanNotification(arguments: Any?, result: @escaping FlutterResult) {
    let debugLogs = debugLogsEnabled(arguments)
    guard let notification = notificationFromItem(arguments) else {
      log("schedulePlanNotification ignored: invalid arguments", enabled: debugLogs)
      result(nil)
      return
    }
    guard notification.scheduledAt > Date() else {
      log(
        "schedulePlanNotification ignored: past date id=\(notification.id) scheduledAt=\(notification.scheduledAt)",
        enabled: debugLogs
      )
      result(nil)
      return
    }

    let center = UNUserNotificationCenter.current()
    add(notification, center: center, debugLogs: debugLogs)
    logPendingRequests(context: "schedulePlanNotification", enabled: debugLogs)
    result(nil)
  }

  private func add(
    _ notification: PlanNotificationPayload,
    center: UNUserNotificationCenter,
    debugLogs: Bool
  ) {
    let request = requestFor(notification)
    log(
      "add id=\(notification.id) scheduledAt=\(notification.scheduledAt) timeInterval=\(notification.scheduledAt.timeIntervalSinceNow)",
      enabled: debugLogs
    )
    center.add(request) { error in
      if let error = error {
        self.log("add error id=\(notification.id) error=\(error.localizedDescription)", enabled: debugLogs)
        return
      }
      self.log("add success id=\(notification.id)", enabled: debugLogs)
      self.logPendingRequests(context: "add completion", enabled: debugLogs)
    }
  }

  private func requestFor(_ notification: PlanNotificationPayload) -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    content.title = notification.title
    content.body = notification.body
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(
      timeInterval: max(1, notification.scheduledAt.timeIntervalSinceNow),
      repeats: false
    )
    return UNNotificationRequest(
      identifier: notification.id,
      content: content,
      trigger: trigger
    )
  }

  private func cancelPlanNotifications() {
    let ids = scheduledIds()
    UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    UserDefaults.standard.set([], forKey: Self.scheduledIdsKey)
  }

  private func notificationsFromArguments(_ arguments: Any?) -> [PlanNotificationPayload] {
    guard let root = arguments as? [String: Any],
          let items = root["notifications"] as? [[String: Any]]
    else {
      return []
    }
    return items.compactMap(notificationFromItem)
  }

  private func notificationFromItem(_ item: Any?) -> PlanNotificationPayload? {
    guard let item = item as? [String: Any],
          let id = item["id"] as? String,
          let title = item["title"] as? String,
          let body = item["body"] as? String,
          let scheduledAtMillis = item["scheduledAtMillis"] as? NSNumber
    else {
      return nil
    }
    return PlanNotificationPayload(
      id: id,
      title: title,
      body: body,
      scheduledAt: Date(timeIntervalSince1970: scheduledAtMillis.doubleValue / 1000)
    )
  }

  private func scheduledIds() -> [String] {
    UserDefaults.standard.stringArray(forKey: Self.scheduledIdsKey) ?? []
  }

  private func saveScheduledIds(_ ids: [String]) {
    UserDefaults.standard.set(ids, forKey: Self.scheduledIdsKey)
  }

  private func debugLogsEnabled(_ arguments: Any?) -> Bool {
    guard let root = arguments as? [String: Any],
          let debugLogs = root["debugLogs"] as? Bool
    else {
      return false
    }
    return debugLogs
  }

  private func log(_ message: String, enabled: Bool) {
    if enabled {
      NSLog("[RuniacLocalNotifications][iOS] \(message)")
    }
  }

  private func logPendingRequests(context: String, enabled: Bool) {
    guard enabled else {
      return
    }
    UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
      let identifiers = requests.map(\.identifier).joined(separator: ",")
      self.log("pendingRequests context=\(context) count=\(requests.count) ids=[\(identifiers)]", enabled: true)
    }
  }
}

private struct PlanNotificationPayload {
  let id: String
  let title: String
  let body: String
  let scheduledAt: Date
}
