import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models/workout_briefing_agent.dart';
import '../domain/services/workout_briefing_payload_builder.dart';
import 'local_workout_briefing_cache_store.dart';

typedef WorkoutBriefingCallable =
    Future<Object?> Function(Map<String, Object?> payload);
typedef WorkoutBriefingOwnerUidProvider = String? Function();

/// Talks to `workoutBriefingAgent`. Never throws: a dead key, a rate limit, a
/// malformed response, and a tier change all resolve to a bundle, because the
/// runner is looking at a plan screen where an error banner would be worse than
/// calm generic copy.
class CloudFunctionWorkoutBriefingAgent implements WorkoutBriefingAgent {
  CloudFunctionWorkoutBriefingAgent({
    FirebaseFunctions? functions,
    WorkoutBriefingCallable? callable,
    this.payloadBuilder = const WorkoutBriefingPayloadBuilder(),
  }) : _callable =
           callable ??
           _firebaseCallable(
             functions ??
                 FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
           );

  final WorkoutBriefingCallable _callable;
  final WorkoutBriefingPayloadBuilder payloadBuilder;

  @override
  Future<WorkoutBriefingBundle> explainPlannedWorkout(
    WorkoutBriefingRequest request,
  ) async {
    try {
      final bundle = _bundleFromResponse(
        await _callable(payloadBuilder.build(request)),
      );
      if (bundle != null) return bundle;
    } on FirebaseFunctionsException catch (error) {
      // Defence-in-depth: the paywall gate intercepts Basic runners in the UI,
      // so this only fires on a direct call racing a tier change.
      if (_isPremiumRequiredDenial(error)) {
        return premiumRequiredWorkoutBriefingBundle();
      }
    } catch (_) {
      // Keep the workout detail screen usable when the agent cannot answer.
    }
    return fallbackWorkoutBriefingBundle();
  }

  static WorkoutBriefingCallable _firebaseCallable(
    FirebaseFunctions functions,
  ) {
    return (payload) async {
      final result = await functions
          .httpsCallable('workoutBriefingAgent')
          .call<Object?>(payload);
      return result.data;
    };
  }

  static bool _isPremiumRequiredDenial(FirebaseFunctionsException error) {
    if (error.code != 'permission-denied') return false;
    final details = error.details;
    return details is Map &&
        details['reason'] == workoutBriefingPremiumRequiredReason;
  }

  WorkoutBriefingBundle? _bundleFromResponse(Object? response) {
    if (response is! Map) return null;
    final source = response['source'];
    final delivery = response['delivery'];
    final sections = _sectionsFromResponse(response['sections']);
    if (sections == null) return null;
    if (source == 'agent' && delivery == 'generated') {
      return WorkoutBriefingBundle(
        sections: sections,
        source: WorkoutBriefingSource.generated,
      );
    }
    if (source == 'quota' && delivery == 'quota') {
      final retryAfterDate = response['retryAfterDate'];
      return WorkoutBriefingBundle(
        sections: sections,
        source: WorkoutBriefingSource.quota,
        retryAfterDate: retryAfterDate is String ? retryAfterDate : null,
      );
    }
    if (source == 'unavailable' && delivery == 'fallback') {
      return WorkoutBriefingBundle(
        sections: sections,
        source: WorkoutBriefingSource.fallback,
      );
    }
    return null;
  }

  WorkoutBriefingSections? _sectionsFromResponse(Object? value) {
    if (value is! Map) return null;
    final todaySession = value['todaySession'];
    final whyItHelps = value['whyItHelps'];
    final howItFeels = value['howItFeels'];
    final beforeYouStart = value['beforeYouStart'];
    if (todaySession is! String ||
        whyItHelps is! String ||
        howItFeels is! String ||
        beforeYouStart is! String) {
      return null;
    }
    return WorkoutBriefingSections(
      todaySession: todaySession,
      whyItHelps: whyItHelps,
      howItFeels: howItFeels,
      beforeYouStart: beforeYouStart,
    );
  }
}

/// Caching is composed around the agent instead of living inside the callable
/// adapter, so TTL and fingerprint invalidation are testable without mocking
/// Firebase Functions, and a widget test can inject a bare stub with no
/// SharedPreferences at all.
class CachingWorkoutBriefingAgent implements WorkoutBriefingAgent {
  CachingWorkoutBriefingAgent({
    required this.delegate,
    this.payloadBuilder = const WorkoutBriefingPayloadBuilder(),
    LocalWorkoutBriefingCacheStore? cacheStore,
    WorkoutBriefingOwnerUidProvider? ownerUidProvider,
    DateTime Function()? clock,
  }) : _cacheStore =
           cacheStore ??
           const SharedPreferencesLocalWorkoutBriefingCacheStore(),
       _ownerUidProvider = ownerUidProvider ?? _currentFirebaseOwnerUid,
       _clock = clock ?? DateTime.now;

  final WorkoutBriefingAgent delegate;
  final LocalWorkoutBriefingCacheStore _cacheStore;
  final WorkoutBriefingOwnerUidProvider _ownerUidProvider;
  final DateTime Function() _clock;
  final WorkoutBriefingPayloadBuilder payloadBuilder;

  /// Longer than the activity-feedback cache because planned-workout copy is
  /// static until the plan itself changes, and the content fingerprint already
  /// invalidates on change.
  static const cacheTtl = Duration(days: 7);

  @override
  Future<WorkoutBriefingBundle> explainPlannedWorkout(
    WorkoutBriefingRequest request,
  ) async {
    final address = _cacheAddressFor(request);
    if (address != null) {
      final cached = await _loadCachedBundle(address);
      if (cached != null) return cached;
    }
    final bundle = await delegate.explainPlannedWorkout(request);
    if (bundle.isGenerated && address != null) {
      await _saveGeneratedBundle(address, bundle);
    }
    return bundle;
  }

  _WorkoutBriefingCacheAddress? _cacheAddressFor(
    WorkoutBriefingRequest request,
  ) {
    final workoutIdentity = payloadBuilder.cacheIdentityFor(request);
    if (workoutIdentity == null) return null;
    String? ownerUid;
    try {
      ownerUid = _ownerUidProvider()?.trim();
    } catch (_) {
      return null;
    }
    if (ownerUid == null || ownerUid.isEmpty) return null;
    return _WorkoutBriefingCacheAddress(
      ownerUid: ownerUid,
      workoutIdentity: workoutIdentity,
    );
  }

  Future<WorkoutBriefingBundle?> _loadCachedBundle(
    _WorkoutBriefingCacheAddress address,
  ) async {
    try {
      final entry = await _cacheStore.load(
        ownerUid: address.ownerUid,
        workoutIdentity: address.workoutIdentity,
      );
      if (entry == null) return null;
      final age = _clock().toUtc().difference(entry.cachedAt);
      if (age.isNegative || age > cacheTtl) {
        await _cacheStore.remove(
          ownerUid: address.ownerUid,
          workoutIdentity: address.workoutIdentity,
        );
        return null;
      }
      return WorkoutBriefingBundle(
        sections: entry.sections,
        source: WorkoutBriefingSource.generated,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveGeneratedBundle(
    _WorkoutBriefingCacheAddress address,
    WorkoutBriefingBundle bundle,
  ) async {
    try {
      await _cacheStore.save(
        ownerUid: address.ownerUid,
        workoutIdentity: address.workoutIdentity,
        entry: LocalWorkoutBriefingCacheEntry(
          cachedAt: _clock().toUtc(),
          sections: bundle.sections,
        ),
      );
    } catch (_) {
      // A cache write failure must never cost the runner their briefing.
    }
  }
}

class _WorkoutBriefingCacheAddress {
  const _WorkoutBriefingCacheAddress({
    required this.ownerUid,
    required this.workoutIdentity,
  });

  final String ownerUid;
  final String workoutIdentity;
}

String? _currentFirebaseOwnerUid() => FirebaseAuth.instance.currentUser?.uid;
