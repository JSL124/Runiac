import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testCadenceEstimatorAcceptsSlowBeginnerCadence() {
    var estimator = RuniacCadenceEstimator()
    let start = Date(timeIntervalSince1970: 1_000)

    XCTAssertNil(estimator.cadence(
      currentCadenceHz: nil,
      cumulativeSteps: 0,
      startDate: start,
      endDate: start
    ))
    XCTAssertEqual(estimator.cadence(
      currentCadenceHz: nil,
      cumulativeSteps: 10,
      startDate: start,
      endDate: start.addingTimeInterval(10)
    ), 60)
  }

  func testCadenceEstimatorDoesNotFabricateStationaryCadence() {
    var estimator = RuniacCadenceEstimator()
    let start = Date(timeIntervalSince1970: 1_000)

    XCTAssertNil(estimator.cadence(
      currentCadenceHz: nil,
      cumulativeSteps: 0,
      startDate: start,
      endDate: start
    ))
    XCTAssertNil(estimator.cadence(
      currentCadenceHz: nil,
      cumulativeSteps: 0,
      startDate: start,
      endDate: start.addingTimeInterval(20)
    ))
  }

  func testCadenceEstimatorRejectsOutOfRangeNativeCadence() {
    var estimator = RuniacCadenceEstimator()

    XCTAssertEqual(estimator.cadence(
      currentCadenceHz: 1,
      cumulativeSteps: 0,
      startDate: .distantPast,
      endDate: .distantFuture
    ), 60)
    XCTAssertNil(estimator.cadence(
      currentCadenceHz: 5,
      cumulativeSteps: 0,
      startDate: .distantPast,
      endDate: .distantFuture
    ))
  }

  func testCadenceEstimatorAcceptsExactContractBoundaries() {
    for cadenceSpm in [40.0, 240.0] {
      var estimator = RuniacCadenceEstimator()

      XCTAssertEqual(estimator.cadence(
        currentCadenceHz: cadenceSpm / 60,
        cumulativeSteps: 0,
        startDate: .distantPast,
        endDate: .distantFuture
      ), Int(cadenceSpm))
    }
  }

  func testCadenceEstimatorRejectsValuesOutsideContractBoundaries() {
    for cadenceSpm in [39.0, 241.0] {
      var estimator = RuniacCadenceEstimator()

      XCTAssertNil(estimator.cadence(
        currentCadenceHz: cadenceSpm / 60,
        cumulativeSteps: 0,
        startDate: .distantPast,
        endDate: .distantFuture
      ))
      XCTAssertTrue(estimator.rejectedFiniteCadence)
    }
  }

  func testCadenceEstimatorRejectsNonFiniteNativeCadence() {
    for cadence in [Double.nan, Double.infinity, -Double.infinity] {
      var estimator = RuniacCadenceEstimator()

      XCTAssertNil(estimator.cadence(
        currentCadenceHz: cadence,
        cumulativeSteps: 0,
        startDate: .distantPast,
        endDate: .distantFuture
      ))
      XCTAssertTrue(estimator.rejectedNonFiniteCadence)
      XCTAssertNil(estimator.rejectedCadence)
    }
  }

  func testCadenceEstimatorRejectsHugeFiniteNativeCadenceBeforeIntegerConversion() {
    var estimator = RuniacCadenceEstimator()

    XCTAssertNil(estimator.cadence(
      currentCadenceHz: Double(Int.max) / 60,
      cumulativeSteps: 0,
      startDate: .distantPast,
      endDate: .distantFuture
    ))
    XCTAssertTrue(estimator.rejectedFiniteCadence)
    XCTAssertNil(estimator.rejectedCadence)
  }

  func testListenGenerationRejectsCancelledAndReplacedStreams() {
    var generation = RuniacListenGeneration()
    let first = generation.begin()

    XCTAssertTrue(generation.accepts(first))
    generation.cancel()
    XCTAssertFalse(generation.accepts(first))

    let second = generation.begin()
    XCTAssertFalse(generation.accepts(first))
    XCTAssertTrue(generation.accepts(second))
  }

  func testPermissionStatusMappingPreservesUndeterminedState() {
    XCTAssertEqual(RuniacMotionPermission.status(for: .authorized), "granted")
    XCTAssertEqual(RuniacMotionPermission.status(for: .denied), "denied")
    XCTAssertEqual(RuniacMotionPermission.status(for: .restricted), "restricted")
    XCTAssertEqual(RuniacMotionPermission.status(for: .notDetermined), "unknown")
  }

  func testPermissionRequestCompletesFromQueryExactlyOnce() {
    var status = "unknown"
    var timeout: (() -> Void)?
    var results: [String] = []
    let completion = expectation(description: "permission result")
    let channel = RuniacPhoneMotionCadenceChannel(
      permissionStatusProvider: { status },
      permissionQuery: { callback in
        status = "granted"
        callback()
      },
      permissionTimeoutScheduler: { timeout = $0 }
    )

    channel.requestPermission { value in
      results.append(value as? String ?? "invalid")
      completion.fulfill()
    }
    wait(for: [completion], timeout: 1)
    timeout?()

    XCTAssertEqual(results, ["granted"])
  }

  func testPermissionRequestTimesOutExactlyOnce() {
    var queryCompletion: (() -> Void)?
    var results: [String] = []
    let completion = expectation(description: "permission timeout")
    let channel = RuniacPhoneMotionCadenceChannel(
      permissionStatusProvider: { "unknown" },
      permissionQuery: { queryCompletion = $0 },
      permissionTimeoutScheduler: { $0() }
    )

    channel.requestPermission { value in
      results.append(value as? String ?? "invalid")
      completion.fulfill()
    }
    wait(for: [completion], timeout: 1)
    queryCompletion?()
    let mainQueueDrained = expectation(description: "main queue drained")
    DispatchQueue.main.async { mainQueueDrained.fulfill() }
    wait(for: [mainQueueDrained], timeout: 1)

    XCTAssertEqual(results, ["unknown"])
  }

  func testPermissionRequestShortCircuitsDeniedAndRestricted() {
    for status in ["denied", "restricted"] {
      var queried = false
      var scheduledTimeout = false
      var result: String?
      let channel = RuniacPhoneMotionCadenceChannel(
        permissionStatusProvider: { status },
        permissionQuery: { _ in queried = true },
        permissionTimeoutScheduler: { _ in scheduledTimeout = true }
      )

      channel.requestPermission { result = $0 as? String }

      XCTAssertEqual(result, status)
      XCTAssertFalse(queried)
      XCTAssertFalse(scheduledTimeout)
    }
  }

}
