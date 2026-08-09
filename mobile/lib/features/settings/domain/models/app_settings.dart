enum DistanceUnit { kilometers, miles }

class AppSettings {
  const AppSettings({
    required this.distanceUnit,
    required this.hapticFeedbackEnabled,
    required this.keepScreenOnDuringRun,
  });

  static const defaults = AppSettings(
    distanceUnit: DistanceUnit.kilometers,
    hapticFeedbackEnabled: true,
    keepScreenOnDuringRun: false,
  );

  final DistanceUnit distanceUnit;
  final bool hapticFeedbackEnabled;
  final bool keepScreenOnDuringRun;

  AppSettings copyWith({
    DistanceUnit? distanceUnit,
    bool? hapticFeedbackEnabled,
    bool? keepScreenOnDuringRun,
  }) {
    return AppSettings(
      distanceUnit: distanceUnit ?? this.distanceUnit,
      hapticFeedbackEnabled:
          hapticFeedbackEnabled ?? this.hapticFeedbackEnabled,
      keepScreenOnDuringRun:
          keepScreenOnDuringRun ?? this.keepScreenOnDuringRun,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AppSettings &&
        other.distanceUnit == distanceUnit &&
        other.hapticFeedbackEnabled == hapticFeedbackEnabled &&
        other.keepScreenOnDuringRun == keepScreenOnDuringRun;
  }

  @override
  int get hashCode {
    return Object.hash(
      distanceUnit,
      hapticFeedbackEnabled,
      keepScreenOnDuringRun,
    );
  }
}
