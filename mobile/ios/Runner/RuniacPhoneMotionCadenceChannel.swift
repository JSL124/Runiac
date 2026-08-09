import CoreMotion
import Flutter
import UIKit

struct RuniacCadenceEstimator {
  private static let windowSeconds: TimeInterval = 5
  private static let minimumWindowSteps = 3
  private static let minimumCadenceSpm = 40
  private static let maximumCadenceSpm = 240

  private var baselineSteps: Int?
  private var baselineDate: Date?
  private(set) var rejectedCadence: Int?
  private(set) var rejectedFiniteCadence = false
  private(set) var rejectedNonFiniteCadence = false

  mutating func reset() {
    baselineSteps = nil
    baselineDate = nil
    rejectedCadence = nil
    rejectedFiniteCadence = false
    rejectedNonFiniteCadence = false
  }

  mutating func cadence(
    currentCadenceHz: Double?,
    cumulativeSteps: Int,
    startDate: Date,
    endDate: Date
  ) -> Int? {
    rejectedCadence = nil
    rejectedFiniteCadence = false
    rejectedNonFiniteCadence = false
    if let currentCadenceHz = currentCadenceHz {
      return validated(currentCadenceHz * 60)
    }

    if baselineSteps == nil || baselineDate == nil {
      baselineSteps = cumulativeSteps
      baselineDate = startDate
      return nil
    }
    guard let baselineSteps = baselineSteps, let baselineDate = baselineDate else {
      return nil
    }

    let stepDelta = cumulativeSteps - baselineSteps
    let elapsedSeconds = endDate.timeIntervalSince(baselineDate)
    guard stepDelta >= Self.minimumWindowSteps,
          elapsedSeconds >= Self.windowSeconds
    else {
      return nil
    }

    self.baselineSteps = cumulativeSteps
    self.baselineDate = endDate
    return validated(Double(stepDelta) / elapsedSeconds * 60)
  }

  private mutating func validated(_ cadence: Double) -> Int? {
    guard cadence.isFinite else {
      rejectedNonFiniteCadence = true
      return nil
    }
    guard cadence >= Double(Self.minimumCadenceSpm),
          cadence <= Double(Self.maximumCadenceSpm)
    else {
      rejectedFiniteCadence = true
      if cadence >= -1_000_000, cadence <= 1_000_000 {
        rejectedCadence = Int(cadence.rounded())
      }
      return nil
    }
    return Int(cadence.rounded())
  }
}

struct RuniacListenGeneration {
  private(set) var current: UInt64 = 0

  mutating func begin() -> UInt64 {
    current &+= 1
    return current
  }

  mutating func cancel() {
    current &+= 1
  }

  func accepts(_ generation: UInt64) -> Bool {
    generation == current
  }
}

enum RuniacMotionPermission {
  static func status(for authorizationStatus: CMAuthorizationStatus) -> String {
    switch authorizationStatus {
    case .authorized:
      return "granted"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "unknown"
    @unknown default:
      return "unknown"
    }
  }
}

final class RuniacPhoneMotionCadenceChannel: NSObject, FlutterStreamHandler {
  private static let methodChannelName = "runiac/phone_motion_cadence"
  private static let eventChannelName = "runiac/phone_motion_cadence_events"
  private let pedometer: CMPedometer
  private let stateQueue = DispatchQueue(label: "runiac.phone-motion-cadence.state")
  private let permissionStatusProvider: () -> String
  private let permissionQuery: (@escaping () -> Void) -> Void
  private let permissionTimeoutScheduler: (@escaping () -> Void) -> Void
  private var eventSink: FlutterEventSink?
  private var listenGeneration = RuniacListenGeneration()
  private var estimator = RuniacCadenceEstimator()
  private var acceptedCadenceCount = 0
  private var filteredCadenceCount = 0
  private var nativeErrorCount = 0

  init(
    pedometer: CMPedometer = CMPedometer(),
    permissionStatusProvider: @escaping () -> String = RuniacPhoneMotionCadenceChannel.permissionStatus,
    permissionQuery: ((@escaping () -> Void) -> Void)? = nil,
    permissionTimeoutScheduler: @escaping (@escaping () -> Void) -> Void = { completion in
      DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: completion)
    }
  ) {
    self.pedometer = pedometer
    self.permissionStatusProvider = permissionStatusProvider
    self.permissionQuery = permissionQuery ?? { completion in
      let now = Date()
      pedometer.queryPedometerData(
        from: now.addingTimeInterval(-1),
        to: now
      ) { _, _ in
        completion()
      }
    }
    self.permissionTimeoutScheduler = permissionTimeoutScheduler
  }

  static func register(with messenger: FlutterBinaryMessenger) {
    let methodChannel = FlutterMethodChannel(
      name: methodChannelName,
      binaryMessenger: messenger
    )
    let eventChannel = FlutterEventChannel(
      name: eventChannelName,
      binaryMessenger: messenger
    )
    let handler = RuniacPhoneMotionCadenceChannel()
    methodChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(CMPedometer.isStepCountingAvailable())
      case "requestPermission":
        handler.requestPermission(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    eventChannel.setStreamHandler(handler)
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    guard CMPedometer.isStepCountingAvailable() else {
      events(Self.diagnosticEvent(
        reason: "unavailable",
        availabilityStatus: "unavailable"
      ))
      events(FlutterEndOfEventStream)
      return nil
    }

    let permissionStatus = Self.permissionStatus()
    if permissionStatus == "denied" || permissionStatus == "restricted" {
      events(Self.diagnosticEvent(
        reason: permissionStatus == "denied" ? "permissionDenied" : "permissionRestricted",
        availabilityStatus: "available",
        permissionStatus: permissionStatus
      ))
      events(FlutterEndOfEventStream)
      return nil
    }

    let generation = stateQueue.sync { () -> UInt64 in
      estimator.reset()
      acceptedCadenceCount = 0
      filteredCadenceCount = 0
      nativeErrorCount = 0
      eventSink = events
      return listenGeneration.begin()
    }
    events(Self.diagnosticEvent(
      reason: "streamStarted",
      availabilityStatus: "available",
      permissionStatus: permissionStatus,
      acceptedCadenceCount: 0,
      filteredCadenceCount: 0,
      nativeErrorCount: 0
    ))
    pedometer.startUpdates(from: Date()) { [weak self] data, error in
      self?.stateQueue.async { [weak self] in
        self?.handlePedometerUpdate(data: data, error: error, generation: generation)
      }
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    pedometer.stopUpdates()
    stateQueue.sync {
      listenGeneration.cancel()
      estimator.reset()
      eventSink = nil
    }
    return nil
  }

  private func handlePedometerUpdate(
    data: CMPedometerData?,
    error: Error?,
    generation: UInt64
  ) {
    guard listenGeneration.accepts(generation), eventSink != nil else { return }
    if let error = error {
      nativeErrorCount += 1
      emitDiagnostic(
        reason: "nativeError",
        generation: generation,
        errorCode: String(describing: type(of: error)),
        errorMessage: error.localizedDescription
      )
      return
    }
    guard let data = data else {
      emitDiagnostic(reason: "nilData", generation: generation)
      return
    }
    guard let cadence = cadence(from: data, generation: generation) else { return }
    acceptedCadenceCount += 1
    deliver([
      "type": "sample",
      "recordedAtMillis": millisecondsSinceEpoch(Date()),
      "stepsPerMinute": cadence,
      "confidence": "estimated",
      "acceptedCadenceCount": acceptedCadenceCount,
      "filteredCadenceCount": filteredCadenceCount,
    ], generation: generation)
  }

  private func cadence(from data: CMPedometerData, generation: UInt64) -> Int? {
    let currentCadenceHz: Double?
    if #available(iOS 10.0, *) {
      currentCadenceHz = data.currentCadence?.doubleValue
    } else {
      currentCadenceHz = nil
    }
    let cadence = estimator.cadence(
      currentCadenceHz: currentCadenceHz,
      cumulativeSteps: data.numberOfSteps.intValue,
      startDate: data.startDate,
      endDate: data.endDate
    )
    if estimator.rejectedFiniteCadence {
      filteredCadenceCount += 1
      emitDiagnostic(
        reason: "filteredOutOfRange",
        generation: generation,
        cadence: estimator.rejectedCadence
      )
    } else if estimator.rejectedNonFiniteCadence {
      filteredCadenceCount += 1
      emitDiagnostic(reason: "filteredOutOfRange", generation: generation)
    }
    return cadence
  }

  private static func permissionStatus() -> String {
    if #available(iOS 11.0, *) {
      return RuniacMotionPermission.status(for: CMPedometer.authorizationStatus())
    }
    return "unknown"
  }

  func requestPermission(result: @escaping FlutterResult) {
    let status = permissionStatusProvider()
    guard status == "unknown" else {
      result(status)
      return
    }

    var didComplete = false
    let complete: (String) -> Void = { permissionStatus in
      DispatchQueue.main.async {
        guard !didComplete else { return }
        didComplete = true
        result(permissionStatus)
      }
    }
    permissionQuery {
      complete(self.permissionStatusProvider())
    }
    permissionTimeoutScheduler {
      guard !didComplete else { return }
      didComplete = true
      result(self.permissionStatusProvider())
    }
  }

  private func emitDiagnostic(
    reason: String,
    generation: UInt64,
    cadence: Int? = nil,
    errorCode: String? = nil,
    errorMessage: String? = nil
  ) {
    let event = Self.diagnosticEvent(
      reason: reason,
      availabilityStatus: "available",
      permissionStatus: Self.permissionStatus(),
      cadence: cadence,
      acceptedCadenceCount: acceptedCadenceCount,
      filteredCadenceCount: filteredCadenceCount,
      nativeErrorCount: nativeErrorCount,
      errorCode: errorCode,
      errorMessage: errorMessage
    )
    deliver(event, generation: generation)
  }

  private func deliver(_ event: [String: Any], generation: UInt64) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      let sink = self.stateQueue.sync { () -> FlutterEventSink? in
        guard self.listenGeneration.accepts(generation) else { return nil }
        return self.eventSink
      }
      sink?(event)
    }
  }

  private static func diagnosticEvent(
    reason: String,
    availabilityStatus: String? = nil,
    permissionStatus: String? = nil,
    cadence: Int? = nil,
    acceptedCadenceCount: Int? = nil,
    filteredCadenceCount: Int? = nil,
    nativeErrorCount: Int? = nil,
    errorCode: String? = nil,
    errorMessage: String? = nil
  ) -> [String: Any] {
    var event: [String: Any] = [
      "type": "diagnostic",
      "reason": reason,
    ]
    if let availabilityStatus = availabilityStatus {
      event["availabilityStatus"] = availabilityStatus
    }
    if let permissionStatus = permissionStatus {
      event["permissionStatus"] = permissionStatus
    }
    if let cadence = cadence {
      event["stepsPerMinute"] = cadence
    }
    if let acceptedCadenceCount = acceptedCadenceCount {
      event["acceptedCadenceCount"] = acceptedCadenceCount
    }
    if let filteredCadenceCount = filteredCadenceCount {
      event["filteredCadenceCount"] = filteredCadenceCount
    }
    if let nativeErrorCount = nativeErrorCount {
      event["nativeErrorCount"] = nativeErrorCount
    }
    if let errorCode = errorCode {
      event["errorCode"] = errorCode
    }
    if let errorMessage = errorMessage {
      event["errorMessage"] = errorMessage
    }
    return event
  }

  private func millisecondsSinceEpoch(_ date: Date) -> Int64 {
    return Int64((date.timeIntervalSince1970 * 1000).rounded())
  }
}
