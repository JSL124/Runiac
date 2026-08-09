class RunVoiceSnapshot {
  const RunVoiceSnapshot({
    required this.distanceMeters,
    required this.elapsed,
    required this.averagePace,
    required this.isActive,
    required this.isPaused,
    this.currentPace,
  });

  final int distanceMeters;
  final Duration elapsed;
  final Duration? averagePace;
  final bool isActive;
  final bool isPaused;
  final Duration? currentPace;

  @override
  bool operator ==(Object other) {
    return other is RunVoiceSnapshot &&
        other.distanceMeters == distanceMeters &&
        other.elapsed == elapsed &&
        other.averagePace == averagePace &&
        other.isActive == isActive &&
        other.isPaused == isPaused &&
        other.currentPace == currentPace;
  }

  @override
  int get hashCode {
    return Object.hash(
      distanceMeters,
      elapsed,
      averagePace,
      isActive,
      isPaused,
      currentPace,
    );
  }
}
