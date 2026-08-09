import '../models/runner_public_profile_read_model.dart';

/// How a viewer addresses the runner whose public profile they are opening.
///
/// A leaderboard row carries no uid — the backend snapshot deliberately omits
/// it so the board cannot be read as a uid directory — so a viewer names the
/// runner by the entry they tapped, and the backend resolves the owner.
/// Every other surface (feed, friends, challenges) already holds the uid, so
/// [RunnerPublicProfileQuery.runner] addresses the runner directly.
///
/// [buildId] pins that entry to the aggregation run the viewer actually saw.
/// The monthly refresh reuses one snapshot id and reassigns rank labels, so a
/// rank alone would resolve to whoever holds the position now rather than the
/// runner on screen.
class RunnerPublicProfileQuery {
  const RunnerPublicProfileQuery.leaderboardEntry({
    required this.snapshotId,
    required this.rankLabel,
    required this.buildId,
  }) : uid = '';

  /// Addresses the runner directly by uid. Used by every surface that already
  /// knows the runner it names — feed, friends, challenges — where hiding the
  /// uid the way a leaderboard row does would serve no purpose.
  const RunnerPublicProfileQuery.runner({required this.uid})
    : snapshotId = '',
      rankLabel = '',
      buildId = '';

  final String uid;
  final String snapshotId;
  final String rankLabel;
  final String buildId;

  /// False for demo and preview rows, which have no backing entry at all.
  bool get isResolvable =>
      uid.isNotEmpty ||
      (snapshotId.isNotEmpty && rankLabel.isNotEmpty && buildId.isNotEmpty);

  /// The callable payload. The backend rejects any other shape.
  Map<String, Object?> toPayload() {
    if (uid.isNotEmpty) {
      return <String, Object?>{'uid': uid};
    }
    return <String, Object?>{
      'snapshotId': snapshotId,
      'rankLabel': rankLabel,
      'buildId': buildId,
    };
  }
}

/// Read-only seam for another runner's public profile projection.
abstract interface class RunnerPublicProfileRepository {
  /// Loads the public running-achievement projection for [query], or `null`
  /// when this build has no backend source wired (previews and tests).
  ///
  /// Throws [RunnerPublicProfileFailure] when a source is wired but the
  /// profile cannot be served.
  Future<RunnerPublicProfileReadModel?> loadRunnerPublicProfile({
    required RunnerPublicProfileQuery query,
  });
}

/// No-backend source used by previews, widget tests, and the static build.
/// Returns `null` so the caller keeps whatever it already knows about the
/// runner instead of showing an error for a missing backend.
class UnavailableRunnerPublicProfileRepository
    implements RunnerPublicProfileRepository {
  const UnavailableRunnerPublicProfileRepository();

  @override
  Future<RunnerPublicProfileReadModel?> loadRunnerPublicProfile({
    required RunnerPublicProfileQuery query,
  }) async {
    return null;
  }
}
