import ActivityKit
import Foundation

@available(iOS 16.1, *)
@MainActor
final class RuniacLiveActivityManager {
  static let shared = RuniacLiveActivityManager()

  private var activity: Activity<RuniacRunActivityAttributes>?
  private var latestState: RuniacRunActivityAttributes.ContentState?

  private init() {}

  func start(payload: RuniacLiveActivityPayload) async throws {
    let state = contentState(from: payload)
    latestState = state

    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return
    }

    if activity != nil {
      await updateActivity(with: state)
      return
    }

    let attributes = RuniacRunActivityAttributes()
    if #available(iOS 16.2, *) {
      activity = try Activity.request(
        attributes: attributes,
        content: ActivityContent(state: state, staleDate: nil),
        pushType: nil
      )
    } else {
      activity = try Activity.request(
        attributes: attributes,
        contentState: state,
        pushType: nil
      )
    }
  }

  func update(payload: RuniacLiveActivityPayload) async {
    let state = contentState(from: payload)
    latestState = state
    await updateActivity(with: state)
  }

  func stop() async {
    guard let currentActivity = activity else {
      latestState = nil
      return
    }

    let finalState = latestState ?? RuniacRunActivityAttributes.ContentState(
      title: "Runiac is tracking your run",
      statusLabel: "Finished",
      elapsedTimeLabel: "00:00",
      averagePaceLabel: "--:-- /km",
      distanceLabel: "0.00 km",
      supportCopy: ""
    )

    if #available(iOS 16.2, *) {
      await currentActivity.end(
        ActivityContent(state: finalState, staleDate: nil),
        dismissalPolicy: .immediate
      )
    } else {
      await currentActivity.end(using: finalState, dismissalPolicy: .immediate)
    }

    activity = nil
    latestState = nil
  }

  private func updateActivity(with state: RuniacRunActivityAttributes.ContentState) async {
    guard let currentActivity = activity else {
      return
    }

    if #available(iOS 16.2, *) {
      await currentActivity.update(ActivityContent(state: state, staleDate: nil))
    } else {
      await currentActivity.update(using: state)
    }
  }

  private func contentState(
    from payload: RuniacLiveActivityPayload
  ) -> RuniacRunActivityAttributes.ContentState {
    RuniacRunActivityAttributes.ContentState(
      title: payload.title,
      statusLabel: payload.statusLabel,
      elapsedTimeLabel: payload.elapsedTimeLabel,
      averagePaceLabel: payload.averagePaceLabel,
      distanceLabel: payload.distanceLabel,
      supportCopy: payload.supportCopy
    )
  }
}
