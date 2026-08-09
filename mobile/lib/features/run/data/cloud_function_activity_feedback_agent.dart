import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models/activity_feedback_agent.dart';
import '../domain/services/activity_feedback_payload_builder.dart';
import 'local_activity_feedback_cache_store.dart';

typedef ActivityFeedbackCallable =
    Future<Object?> Function(Map<String, Object?> payload);
typedef ActivityFeedbackOwnerUidProvider = String? Function();

/// Calls the backend AI activity-feedback agent for one finished run.
///
/// Results are cached locally per (owner, run) — see
/// [_ActivityFeedbackCacheAddress] — because the feedback for a completed run
/// never changes, and each generation costs an LLM call against the user's
/// quota. Reopening a run summary must therefore not spend a second one.
///
/// The cache is keyed by owner as well as run so that signing in as a different
/// account on the same device cannot surface someone else's feedback.
class CloudFunctionActivityFeedbackAgent implements ActivityFeedbackAgent {
  CloudFunctionActivityFeedbackAgent({
    FirebaseFunctions? functions,
    ActivityFeedbackCallable? callable,
    this.payloadBuilder = const ActivityFeedbackPayloadBuilder(),
    LocalActivityFeedbackCacheStore? cacheStore,
    ActivityFeedbackOwnerUidProvider? ownerUidProvider,
    DateTime Function()? clock,
  }) : _callable =
           callable ??
           _firebaseCallable(
             functions ??
                 FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
           ),
       _cacheStore =
           cacheStore ??
           const SharedPreferencesLocalActivityFeedbackCacheStore(),
       _ownerUidProvider = ownerUidProvider ?? _currentFirebaseOwnerUid,
       _clock = clock ?? DateTime.now;

  final ActivityFeedbackCallable _callable;
  final LocalActivityFeedbackCacheStore _cacheStore;
  final ActivityFeedbackOwnerUidProvider _ownerUidProvider;
  final DateTime Function() _clock;
  final ActivityFeedbackPayloadBuilder payloadBuilder;

  static const cacheTtl = Duration(hours: 24);

  @override
  Future<ActivityFeedbackBundle> explainRun(
    ActivityFeedbackRequest request,
  ) async {
    final cacheAddress = _cacheAddressFor(request);
    if (cacheAddress != null) {
      final cached = await _loadCachedBundle(cacheAddress);
      if (cached != null) return cached;
    }
    try {
      final payload = payloadBuilder.build(
        summary: request.summary,
        analysis: request.analysis,
      );
      final bundle = _bundleFromResponse(await _callable(payload));
      if (bundle != null) {
        if (bundle.isGenerated && cacheAddress != null) {
          await _saveGeneratedBundle(cacheAddress, bundle);
        }
        return bundle;
      }
    } on FirebaseFunctionsException catch (error) {
      // Defence-in-depth: the paywall gate intercepts Basic runners in the
      // UI, so this only fires on a direct call racing a tier change.
      if (_isPremiumRequiredDenial(error)) {
        return premiumRequiredActivityFeedbackBundle();
      }
      // Keep the summary UI usable when Firebase, quota, or model output fails.
    } catch (_) {
      // Keep the summary UI usable when Firebase, quota, or model output fails.
    }
    return fallbackActivityFeedbackBundle();
  }

  _ActivityFeedbackCacheAddress? _cacheAddressFor(
    ActivityFeedbackRequest request,
  ) {
    final runIdentity = request.cacheIdentity?.trim();
    if (runIdentity == null || runIdentity.isEmpty) return null;
    String? ownerUid;
    try {
      ownerUid = _ownerUidProvider()?.trim();
    } catch (_) {
      return null;
    }
    if (ownerUid == null || ownerUid.isEmpty) return null;
    return _ActivityFeedbackCacheAddress(
      ownerUid: ownerUid,
      runIdentity: runIdentity,
    );
  }

  Future<ActivityFeedbackBundle?> _loadCachedBundle(
    _ActivityFeedbackCacheAddress address,
  ) async {
    try {
      final entry = await _cacheStore.load(
        ownerUid: address.ownerUid,
        runIdentity: address.runIdentity,
      );
      if (entry == null) return null;
      final age = _clock().toUtc().difference(entry.cachedAt);
      if (age.isNegative || age >= cacheTtl) {
        await _removeCacheSafely(address);
        return null;
      }
      return ActivityFeedbackBundle(
        sections: entry.sections,
        source: ActivityFeedbackSource.generated,
      );
    } catch (_) {
      await _removeCacheSafely(address);
      return null;
    }
  }

  Future<void> _saveGeneratedBundle(
    _ActivityFeedbackCacheAddress address,
    ActivityFeedbackBundle bundle,
  ) async {
    try {
      await _cacheStore.save(
        ownerUid: address.ownerUid,
        runIdentity: address.runIdentity,
        entry: LocalActivityFeedbackCacheEntry(
          cachedAt: _clock().toUtc(),
          sections: bundle.sections,
        ),
      );
    } catch (_) {
      // A successful generated response remains usable if local storage fails.
    }
  }

  Future<void> _removeCacheSafely(_ActivityFeedbackCacheAddress address) async {
    try {
      await _cacheStore.remove(
        ownerUid: address.ownerUid,
        runIdentity: address.runIdentity,
      );
    } catch (_) {
      // A stale cache entry must not prevent a fresh callable request.
    }
  }

  static bool _isPremiumRequiredDenial(FirebaseFunctionsException error) {
    if (error.code != 'permission-denied') {
      return false;
    }
    final details = error.details;
    return details is Map &&
        details['reason'] == activityFeedbackPremiumRequiredReason;
  }

  static String? _currentFirebaseOwnerUid() {
    return FirebaseAuth.instance.currentUser?.uid;
  }

  static ActivityFeedbackCallable _firebaseCallable(
    FirebaseFunctions functions,
  ) {
    return (payload) async {
      final result = await functions
          .httpsCallable('activityFeedbackAgent')
          .call(payload);
      return result.data;
    };
  }

  ActivityFeedbackBundle? _bundleFromResponse(Object? data) {
    if (data is! Map<Object?, Object?>) return null;
    final source = data['source'];
    final delivery = data['delivery'];
    final sections = _sectionsFromResponse(data['sections']);
    if (sections == null) return null;
    if (source == 'agent' && delivery == 'generated') {
      return ActivityFeedbackBundle(
        source: ActivityFeedbackSource.generated,
        sections: sections,
      );
    }
    if (source == 'quota' && delivery == 'quota') {
      return ActivityFeedbackBundle(
        source: ActivityFeedbackSource.quota,
        sections: sections,
        retryAfterDate: data['retryAfterDate'] is String
            ? data['retryAfterDate']! as String
            : null,
      );
    }
    if (source == 'unavailable' && delivery == 'fallback') {
      return ActivityFeedbackBundle(
        source: ActivityFeedbackSource.fallback,
        sections: sections,
      );
    }
    return null;
  }

  ActivityFeedbackSections? _sectionsFromResponse(Object? data) {
    if (data is! Map<Object?, Object?>) return null;
    final summary = data['summary'];
    final wentWell = data['wentWell'];
    final improve = data['improve'];
    final nextFocus = data['nextFocus'];
    if (summary is! String ||
        wentWell is! String ||
        improve is! String ||
        nextFocus is! String) {
      return null;
    }
    return ActivityFeedbackSections(
      summary: summary,
      wentWell: wentWell,
      improve: improve,
      nextFocus: nextFocus,
    );
  }
}

class _ActivityFeedbackCacheAddress {
  const _ActivityFeedbackCacheAddress({
    required this.ownerUid,
    required this.runIdentity,
  });

  final String ownerUid;
  final String runIdentity;
}
