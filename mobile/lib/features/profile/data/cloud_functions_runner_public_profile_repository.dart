import 'package:cloud_functions/cloud_functions.dart';

import '../../challenge/domain/models/challenge_enums.dart';
import '../domain/models/runner_public_profile_read_model.dart';
import '../domain/repositories/runner_public_profile_repository.dart';

typedef RunnerPublicProfileCallable =
    Future<Object?> Function(Map<String, Object?> payload);

/// Callable-backed source for another runner's public profile.
///
/// `users/{uid}`, `userProfiles/{uid}`, and `users/{uid}/challengeBadges` are
/// owner-read-only in `firestore.rules`, so this never reads them directly:
/// the `getRunnerPublicProfile` Cloud Function decides what a viewer may see.
class CloudFunctionsRunnerPublicProfileRepository
    implements RunnerPublicProfileRepository {
  CloudFunctionsRunnerPublicProfileRepository({
    FirebaseFunctions? functions,
    RunnerPublicProfileCallable? callable,
  }) : _callable =
           callable ??
           _firebaseCallable(
             functions ??
                 FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
           );

  final RunnerPublicProfileCallable _callable;

  static const _unavailableMessage = 'This runner profile is not available.';
  static const _offlineMessage =
      'Runner profile could not be loaded. Please try again.';

  @override
  Future<RunnerPublicProfileReadModel?> loadRunnerPublicProfile({
    required RunnerPublicProfileQuery query,
  }) async {
    if (!query.isResolvable) {
      throw const RunnerPublicProfileFailure(_unavailableMessage);
    }
    final Object? data;
    try {
      data = await _callable(query.toPayload());
    } on FirebaseFunctionsException catch (error) {
      throw RunnerPublicProfileFailure(_messageForCode(error.code));
    } on Object {
      throw const RunnerPublicProfileFailure(_offlineMessage);
    }
    if (data is! Map<Object?, Object?>) {
      throw const RunnerPublicProfileFailure(_offlineMessage);
    }
    return _readModelFrom(data);
  }

  /// A denial and a missing profile read the same way to a viewer, so neither
  /// discloses whether the runner blocked them or simply does not exist.
  String _messageForCode(String code) {
    return switch (code) {
      'permission-denied' || 'not-found' => _unavailableMessage,
      _ => _offlineMessage,
    };
  }

  RunnerPublicProfileReadModel _readModelFrom(Map<Object?, Object?> data) {
    return RunnerPublicProfileReadModel(
      displayName: _string(data['displayName']),
      avatarInitials: _string(data['avatarInitials']),
      avatarUrl: _string(data['avatarUrl']),
      regionLabel: _string(data['regionLabel']),
      level: _nonNegativeInteger(data['level']),
      levelProgressFraction: _progressFraction(data['levelProgressPercent']),
      totalXp: _nonNegativeIntegerOrNull(data['totalXp']),
      nextLevelXp: _nonNegativeIntegerOrNull(data['nextLevelXp']),
      xpToNextLevel: _nonNegativeIntegerOrNull(data['xpToNextLevel']),
      isMaxLevel: data['isMaxLevel'] == true,
      divisionKey: _string(data['divisionKey']),
      divisionLabel: _string(data['divisionLabel']),
      longestStreakLabel: _string(data['longestStreakLabel']),
      totalDistanceLabel: _string(data['totalDistanceLabel']),
      subscriptionStatusLabel: _string(data['subscriptionStatusLabel']),
      ownedTierIds: _ownedTierIds(data['ownedBadgeTierIds']),
      statsHidden: data['statsHidden'] == true,
    );
  }

  /// Unknown tier ids are skipped rather than thrown on, so a catalog the app
  /// build does not know yet can never blank out the whole profile.
  Set<ChallengeTierId> _ownedTierIds(Object? value) {
    if (value is! List) {
      return const <ChallengeTierId>{};
    }
    final owned = <ChallengeTierId>{};
    for (final raw in value) {
      for (final tier in ChallengeTierId.values) {
        if (tier.wireValue == raw) {
          owned.add(tier);
        }
      }
    }
    return owned;
  }

  String _string(Object? value) => value is String ? value.trim() : '';

  int _nonNegativeInteger(Object? value) {
    return value is num && value >= 0 ? value.toInt() : 0;
  }

  int? _nonNegativeIntegerOrNull(Object? value) {
    return value is num && value >= 0 ? value.toInt() : null;
  }

  double _progressFraction(Object? value) {
    return value is num ? value.clamp(0, 100) / 100 : 0;
  }

  static RunnerPublicProfileCallable _firebaseCallable(
    FirebaseFunctions functions,
  ) {
    return (payload) async {
      final result = await functions
          .httpsCallable('getRunnerPublicProfile')
          .call(payload);
      return result.data;
    };
  }
}
