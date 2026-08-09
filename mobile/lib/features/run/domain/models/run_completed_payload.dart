/// Client-observed raw run completion payload for a future backend boundary.
///
/// The backend must validate these observations before persistence or
/// progression. Trusted reward, competition, entitlement, and publication
/// decisions stay backend-owned.
class RunCompletedPayload {
  const RunCompletedPayload({
    required this.clientRunSessionId,
    required this.startedAt,
    required this.completedAt,
    required this.durationSeconds,
    required this.distanceMeters,
    required this.avgPaceSecondsPerKm,
    required this.source,
    this.caloriesEstimate,
    this.routeLabel,
  });

  final String clientRunSessionId;
  final DateTime startedAt;
  final DateTime completedAt;
  final int durationSeconds;
  final int distanceMeters;
  final int avgPaceSecondsPerKm;
  final int? caloriesEstimate;
  final String? routeLabel;
  final String source;
}
