import 'complete_run_result.dart';

enum FeedPublishDisabledReason {
  notAvailable,
  localOnly,
  notValidated,
  orphanSummary,
  insufficientData,
}

class RunFeedPublishSource {
  const RunFeedPublishSource._({
    required this.activityId,
    required this.cacheIdentity,
    required this.disabledReason,
    required this.allowsCurrentSessionRouteCapture,
    required this.allowsMetricThumbnailFallback,
  });

  const RunFeedPublishSource.enabled({
    required String activityId,
    String? cacheIdentity,
    bool allowsCurrentSessionRouteCapture = false,
    bool allowsMetricThumbnailFallback = true,
  }) : this._(
         activityId: activityId,
         cacheIdentity: cacheIdentity,
         disabledReason: null,
         allowsCurrentSessionRouteCapture: allowsCurrentSessionRouteCapture,
         allowsMetricThumbnailFallback: allowsMetricThumbnailFallback,
       );

  const RunFeedPublishSource.disabled(FeedPublishDisabledReason reason)
    : this._(
        activityId: null,
        cacheIdentity: null,
        disabledReason: reason,
        allowsCurrentSessionRouteCapture: false,
        allowsMetricThumbnailFallback: false,
      );

  factory RunFeedPublishSource.fromCompletion(
    CompleteRunResult result, {
    bool allowsCurrentSessionRouteCapture = true,
  }) {
    final activityId = result.activityId;
    if (activityId.isEmpty) {
      return const RunFeedPublishSource.disabled(
        FeedPublishDisabledReason.notAvailable,
      );
    }
    if (activityId.startsWith('local-') ||
        activityId.startsWith('local_') ||
        activityId.startsWith('static-') ||
        activityId.startsWith('static_')) {
      return const RunFeedPublishSource.disabled(
        FeedPublishDisabledReason.localOnly,
      );
    }
    if (!isCanonicalValidatedCompletion(result)) {
      return const RunFeedPublishSource.disabled(
        FeedPublishDisabledReason.notValidated,
      );
    }
    return RunFeedPublishSource.enabled(
      activityId: activityId,
      cacheIdentity: result.clientRunSessionId,
      allowsCurrentSessionRouteCapture: allowsCurrentSessionRouteCapture,
    );
  }

  static bool isCanonicalValidatedCompletion(CompleteRunResult result) {
    return result.activityId.startsWith('activity_') &&
        result.validationStatus == 'validated';
  }

  final String? activityId;
  final String? cacheIdentity;
  final FeedPublishDisabledReason? disabledReason;
  final bool allowsCurrentSessionRouteCapture;
  final bool allowsMetricThumbnailFallback;

  bool get isPublishable => activityId != null && disabledReason == null;
}
