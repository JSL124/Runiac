import ActivityKit
import SwiftUI
import WidgetKit

@available(iOSApplicationExtension 16.1, *)
struct RuniacRunLiveActivityWidget: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: RuniacRunActivityAttributes.self) { context in
      VStack(alignment: .leading, spacing: 10) {
        HStack {
          Text(context.attributes.brandName)
            .font(.caption.weight(.bold))
            .foregroundStyle(runiacBlue)
          Spacer()
          Text(context.state.statusLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }

        Text(context.state.title)
          .font(.headline.weight(.semibold))

        HStack(alignment: .firstTextBaseline, spacing: 18) {
          metric(label: "TIME", value: context.state.elapsedTimeLabel)
          metric(label: "PACE", value: context.state.averagePaceLabel)
          metric(label: "DIST", value: context.state.distanceLabel)
        }

        if !context.state.supportCopy.isEmpty {
          Text(context.state.supportCopy)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
      }
      .padding()
      .activityBackgroundTint(Color(.systemBackground))
      .activitySystemActionForegroundColor(.orange)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.state.elapsedTimeLabel)
            .font(.caption.weight(.semibold))
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.distanceLabel)
            .font(.caption.weight(.semibold))
        }
        DynamicIslandExpandedRegion(.bottom) {
          Text(context.state.statusLabel)
            .font(.caption)
        }
      } compactLeading: {
        Text(context.state.elapsedTimeLabel)
          .font(.caption2.weight(.semibold))
      } compactTrailing: {
        Text(context.state.distanceLabel)
          .font(.caption2.weight(.semibold))
      } minimal: {
        Text("R")
          .font(.caption2.weight(.bold))
          .foregroundStyle(runiacBlue)
      }
    }
  }

  private var runiacBlue: Color {
    Color(red: 47.0 / 255.0, green: 80.0 / 255.0, blue: 199.0 / 255.0)
  }

  private func metric(label: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(label)
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.subheadline.weight(.semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
