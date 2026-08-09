enum RunMotionSignal { unavailable, unknown, stationary, moving }

class RunMotionEvidence {
  const RunMotionEvidence({
    required this.recordedAt,
    required this.signal,
    this.confidence = 0,
  });

  final DateTime recordedAt;
  final RunMotionSignal signal;
  final double confidence;
}
