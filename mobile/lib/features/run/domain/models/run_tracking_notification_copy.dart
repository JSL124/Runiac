import 'run_notification_display_model.dart';
import 'run_tracking_state.dart';

class RunTrackingNotificationCopy {
  const RunTrackingNotificationCopy({
    required this.title,
    required this.body,
    this.statusLabel = 'Getting GPS ready',
    this.elapsedTimeLabel = '00:00',
    this.currentPaceLabel = '--:-- /km',
    this.distanceLabel = '0.00 km',
    this.supportCopy,
  });

  factory RunTrackingNotificationCopy.fromState(RunTrackingState state) {
    final display = RunNotificationDisplayModel.fromState(state);
    return RunTrackingNotificationCopy.fromDisplayModel(display);
  }

  factory RunTrackingNotificationCopy.fromDisplayModel(
    RunNotificationDisplayModel display,
  ) {
    return RunTrackingNotificationCopy(
      title: display.title,
      body: display.collapsedBody,
      statusLabel: display.statusLabel,
      elapsedTimeLabel: display.elapsedTimeLabel,
      currentPaceLabel: display.currentPaceLabel,
      distanceLabel: display.distanceLabel,
      supportCopy: display.supportCopy,
    );
  }

  static const gettingGpsReady = RunTrackingNotificationCopy(
    title: 'Runiac is tracking your run',
    body: '00:00 • --:-- /km • 0.00 km',
    statusLabel: 'Getting GPS ready',
    elapsedTimeLabel: '00:00',
    currentPaceLabel: '--:-- /km',
    distanceLabel: '0.00 km',
    supportCopy: 'Keep moving in an open area.',
  );

  final String title;
  final String body;
  final String statusLabel;
  final String elapsedTimeLabel;
  final String currentPaceLabel;
  final String distanceLabel;
  final String? supportCopy;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RunTrackingNotificationCopy &&
            other.title == title &&
            other.body == body &&
            other.statusLabel == statusLabel &&
            other.elapsedTimeLabel == elapsedTimeLabel &&
            other.currentPaceLabel == currentPaceLabel &&
            other.distanceLabel == distanceLabel &&
            other.supportCopy == supportCopy;
  }

  @override
  int get hashCode => Object.hash(
    title,
    body,
    statusLabel,
    elapsedTimeLabel,
    currentPaceLabel,
    distanceLabel,
    supportCopy,
  );
}
