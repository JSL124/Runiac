import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct RuniacRunActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    let title: String
    let statusLabel: String
    let elapsedTimeLabel: String
    let averagePaceLabel: String
    let distanceLabel: String
    let supportCopy: String
  }

  let brandName: String = "RUNIAC"
}
