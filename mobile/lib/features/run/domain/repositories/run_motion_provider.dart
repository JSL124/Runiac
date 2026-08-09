import '../models/run_motion_evidence.dart';

abstract interface class RunMotionProvider {
  Future<void> start({required DateTime startedAt});

  Future<void> pause();

  Future<void> resume({
    required DateTime resumedAt,
    required Duration trackingOffset,
  });

  Future<void> stop();

  Iterable<RunMotionEvidence> evidenceBetween({
    required Duration fromTrackingOffset,
    required Duration toTrackingOffset,
    required DateTime startedAt,
  });
}

class NoopRunMotionProvider implements RunMotionProvider {
  const NoopRunMotionProvider();

  @override
  Future<void> start({required DateTime startedAt}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume({
    required DateTime resumedAt,
    required Duration trackingOffset,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Iterable<RunMotionEvidence> evidenceBetween({
    required Duration fromTrackingOffset,
    required Duration toTrackingOffset,
    required DateTime startedAt,
  }) {
    return const <RunMotionEvidence>[];
  }
}
