import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:runiac_app/core/assets/runiac_assets.dart';
import 'package:runiac_app/core/characters/runner_character.dart';
import 'package:runiac_app/core/theme/runiac_colors.dart';
import 'package:runiac_app/core/widgets/runiac_back_header.dart';

import 'advanced_analysis_screen.dart';
import '../data/cloud_function_activity_feedback_agent.dart';
import '../domain/models/activity_feedback_agent.dart';
import '../domain/models/advanced_analysis_snapshot.dart';
import '../domain/models/complete_run_result.dart';
import '../domain/models/local_run_completion_payload.dart';
import '../domain/models/coaching_summary_snapshot.dart';
import '../domain/models/pace_graph_snapshot.dart';
import '../domain/models/run_feed_publish_source.dart';
import '../domain/models/run_location_sample.dart';
import '../domain/models/run_route_snapshot.dart';
import '../domain/models/run_summary_snapshot.dart';
import '../domain/services/advanced_analysis_snapshot_builder.dart';
import '../../feed/data/feed_publish/feed_publish_service.dart';
import '../../feed/data/feed_publish/feed_thumbnail_artifact.dart';
import '../../feed/data/feed_publish/feed_thumbnail_capture.dart';
import '../../feed/data/feed_publish/history_artifact_resolver.dart';
import '../../feed/data/feed_publish/firebase_feed_publish_gateway.dart';
import '../../feed/domain/models/feed_display_models.dart';
import '../../feed/presentation/current_session_feed_store.dart';
import '../../paywall/presentation/premium_gate.dart';
import '../../paywall/presentation/premium_paywall_sheet.dart';
import '../../you/presentation/widgets/activity_route_preview.dart';
import '../../you/presentation/widgets/activity_route_mapbox_snapshot_provider.dart';
import '../../you/presentation/current_session_activity_history.dart';
import 'run_repository_scope.dart';
import 'data/run_completion_demo_snapshots.dart';
import 'widgets/completed_route_map_surface.dart';
import 'widgets/mapbox_runtime_config.dart';
import 'widgets/advanced_analysis/advanced_analysis_splits_table.dart';
import 'widgets/activity_feedback_overlay.dart';
import 'widgets/share_achievement_sheet.dart';
import 'widgets/share_route_to_feed_sheet.dart';
import 'xp_update_screen.dart';

part 'view_summary_low_data.dart';
part 'view_summary_map_widgets.dart';
part 'view_summary_metrics.dart';
part 'view_summary_pace.dart';
part 'view_summary_analysis.dart';
part 'view_summary_coaching.dart';
part 'view_summary_actions.dart';
part 'view_summary_map_painter.dart';
part 'view_summary_pace_painter.dart';

const _rBlue = Color(0xFF2F51C8);
const _rOrange = Color(0xFFFB6414);
const _rWhite = Color(0xFFFFFFFF);
const _rBlue90 = Color(0xE62F51C8);
const _rBlue75 = Color(0xBF2F51C8);
const _rBlue60 = Color(0x992F51C8);
const _rBlue45 = Color(0x732F51C8);
const _rBlue30 = Color(0x4D2F51C8);
const _rBlue18 = Color(0x2E2F51C8);
const _rBlue10 = Color(0x1A2F51C8);
const _rBlue06 = Color(0x0F2F51C8);
const _cardRadius = 20.0;
const _paceChartYAxisWidth = 38.0;
const _paceChartAxisGap = 4.0;
const _paceChartHorizontalPlotInset = 16.0;
const _paceChartXAxisLabelWidth = 32.0;

@visibleForTesting
double paceChartDisplayProgressForPoint({
  required int index,
  required int pointCount,
  required double rawProgressFraction,
}) {
  if (pointCount <= 1 || index <= 0) {
    return 0;
  }
  if (index >= pointCount - 1) {
    return 1;
  }
  return rawProgressFraction.clamp(0.0, 1.0);
}

/// The post-run summary — the screen a runner lands on when a run ends.
///
/// It shows the distance/time/pace headline, the route, splits and the pace
/// graph, the XP earned, and the entry points to the deeper Premium surfaces
/// (Advanced Analysis, AI activity feedback, sharing).
///
/// The same screen is reached two ways: straight from finishing a run, and by
/// reopening a past run from the activity history. It therefore takes a
/// completed result rather than live tracking state, so both paths render
/// identically.
class ViewSummaryScreen extends StatelessWidget {
  const ViewSummaryScreen({
    super.key,
    this.summary = defaultRunSummarySnapshot,
    this.completionResult,
    this.completionPayload,
    this.showXpUpdateAction = true,
    this.showLowDataSaveAction = true,
    this.mapboxAccessToken,
    this.mapboxBuilder,
    this.feedPublishService,
    this.historyArtifactResolver,
    this.feedPublishSource,
    this.activityFeedbackAgent,
    this.activityFeedbackCacheIdentity,
  });

  final RunSummarySnapshot summary;
  final CompleteRunResult? completionResult;
  final LocalRunCompletionPayload? completionPayload;
  final bool showXpUpdateAction;
  final bool showLowDataSaveAction;
  final String? mapboxAccessToken;
  final CompletedRouteMapboxBuilder? mapboxBuilder;
  final FeedPublishService? feedPublishService;
  final HistoryArtifactResolver? historyArtifactResolver;
  final RunFeedPublishSource? feedPublishSource;
  final ActivityFeedbackAgent? activityFeedbackAgent;
  final String? activityFeedbackCacheIdentity;

  void _showSoonMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showShareRouteToFeed(
    BuildContext context,
    RunSummarySnapshot summary,
  ) async {
    final publishSource = _effectiveFeedPublishSource;
    final artifact = await _resolveHistoryArtifact(context, summary);
    if (!context.mounted) return;
    final authorProfile =
        CurrentSessionFeedScope.maybeRead(context)?.authorProfile ??
        FeedAuthorProfileSnapshot.fallback();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (sheetContext) => ShareRouteToFeedSheet(
        summary: summary,
        artifact: artifact,
        authorProfile: authorProfile,
        postingUnavailableMessage: _postingUnavailableMessageFor(publishSource),
        onCancel: () => Navigator.of(sheetContext).pop(),
        onConfirm: () async {
          final activityId = publishSource.activityId;
          if (activityId == null || activityId.isEmpty || artifact == null) {
            throw StateError('This run is not ready to post yet.');
          }
          final response =
              await (feedPublishService ??
                      FeedPublishService(gateway: FirebaseFeedPublishGateway()))
                  .publishAfterConfirmation(
                    activityId: activityId,
                    artifact: artifact,
                  );
          if (context.mounted) {
            CurrentSessionFeedScope.maybeRead(
              context,
            )?.cachePublishedThumbnail(response.postId, artifact.pngBytes);
            _showSoonMessage(context, 'Route shared to Feed.');
          }
        },
      ),
    );
  }

  String? _postingUnavailableMessageFor(RunFeedPublishSource source) {
    switch (source.disabledReason) {
      case null:
        return null;
      case FeedPublishDisabledReason.localOnly:
        return 'This run is still local. Save it to your account before posting to Feed.';
      case FeedPublishDisabledReason.notValidated:
        return 'This run is still being validated. Try posting again after validation finishes.';
      case FeedPublishDisabledReason.orphanSummary:
        return 'This history item is missing its validated activity record, so it cannot be posted yet.';
      case FeedPublishDisabledReason.insufficientData:
        return 'This run does not have enough validated distance and time data to post.';
      case FeedPublishDisabledReason.notAvailable:
        return 'This run is not ready to post yet.';
    }
  }

  Future<FeedThumbnailArtifact?> _resolveHistoryArtifact(
    BuildContext context,
    RunSummarySnapshot summary,
  ) async {
    final source = _effectiveFeedPublishSource;
    final activityId = source.activityId;
    final cacheIdentity = source.cacheIdentity;
    final thumbnailIdentity =
        cacheIdentity ?? activityId ?? 'local-summary-preview';
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final request = ActivityRouteThumbnailRequest(
      route: summary.route,
      logicalSize: const Size(88, 88),
      devicePixelRatio: devicePixelRatio,
      allowExternalStaticMap: true,
      isDemoRoute: false,
      isCurrentSessionRoute: source.allowsCurrentSessionRouteCapture,
      activityId: thumbnailIdentity,
    );
    final injectedResolver = historyArtifactResolver;
    if (injectedResolver != null) {
      try {
        final resolved = await injectedResolver.resolve(request);
        if (resolved != null) {
          return resolved;
        }
      } on FeedThumbnailCaptureException {
        // Fall through to the rendered summary preview capture below.
      }
    }
    if (summary.route.hasRoute) {
      return _generateRouteThumbnailArtifact(
        summary: summary,
        thumbnailIdentity: thumbnailIdentity,
        devicePixelRatio: devicePixelRatio,
      );
    }
    try {
      final resolved = await CacheOnlyHistoryArtifactResolver().resolve(
        request,
      );
      if (resolved != null) {
        return resolved;
      }
    } on FeedThumbnailCaptureException {
      // Fall through to the scalar-only fallback below when safe.
    }
    if (!summary.route.hasRoute && source.allowsMetricThumbnailFallback) {
      return const MetricHistoryThumbnailGenerator().generate(
        summary: summary,
        devicePixelRatio: devicePixelRatio,
      );
    }
    return null;
  }

  // Shared 344x184 route-thumbnail generation path used both when resolving
  // the Feed-publish preview above and when building the Share-Your-Activity
  // sheet's map panel, so Mapbox token lookup, privacy flags, and DPR wiring
  // are not duplicated between the two call sites.
  Future<FeedThumbnailArtifact> _generateRouteThumbnailArtifact({
    required RunSummarySnapshot summary,
    required String thumbnailIdentity,
    required double devicePixelRatio,
  }) {
    final runtimeConfig = mapboxAccessToken == null
        ? MapboxRuntimeConfig.fromEnvironment()
        : MapboxRuntimeConfig(accessToken: mapboxAccessToken!.trim());
    final snapshotGenerator =
        runtimeConfig.accessToken.isNotEmpty &&
            runtimeConfig.hasPublicAccessToken
        ? MapboxActivityRouteSnapshotThumbnailGenerator(
            accessToken: runtimeConfig.accessToken,
          )
        : null;
    return RouteHistoryThumbnailGenerator(
      snapshotGenerator: snapshotGenerator,
    ).generate(
      request: ActivityRouteThumbnailRequest(
        route: summary.route,
        logicalSize: const Size(344, 184),
        devicePixelRatio: devicePixelRatio,
        allowExternalStaticMap: true,
        isDemoRoute: false,
        isCurrentSessionRoute: true,
        activityId: thumbnailIdentity,
      ),
    );
  }

  RunFeedPublishSource get _effectiveFeedPublishSource {
    final explicit = feedPublishSource;
    if (explicit != null) {
      return explicit;
    }
    final result = completionResult;
    if (result == null) {
      return const RunFeedPublishSource.disabled(
        FeedPublishDisabledReason.notAvailable,
      );
    }
    return RunFeedPublishSource.fromCompletion(result);
  }

  Future<void> _goHomeFromSummary(
    BuildContext context, {
    required bool hasSufficientData,
  }) async {
    if (!hasSufficientData) {
      final decision = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.48),
        builder: (context) => const _LowDataSaveDecisionSheet(),
      );
      if (!context.mounted || decision == null) {
        return;
      }
      if (decision) {
        final result = completionResult;
        final payload = completionPayload;
        if (result != null && payload != null) {
          final store = CurrentSessionActivityHistoryScope.maybeOf(context);
          final savePayload = payload.copyWith(userConfirmedLowDataSave: true);
          try {
            await store?.saveCompletedRun(result, payload: savePayload);
          } catch (error, stackTrace) {
            FlutterError.reportError(
              FlutterErrorDetails(
                exception: error,
                stack: stackTrace,
                library: 'runiac run summary',
                context: ErrorDescription('saving a low-data run locally'),
              ),
            );
            return;
          }
          if (!context.mounted) {
            return;
          }
          if (store != null) {
            unawaited(
              store
                  .syncPendingRuns(RunRepositoryScope.of(context))
                  .catchError(
                    (Object error, StackTrace stackTrace) =>
                        FlutterError.reportError(
                          FlutterErrorDetails(
                            exception: error,
                            stack: stackTrace,
                            library: 'runiac run summary',
                            context: ErrorDescription(
                              'syncing a saved low-data run',
                            ),
                          ),
                        ),
                  ),
            );
          }
        }
      }
    }

    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final displayedSummary = completionResult?.summary ?? summary;
    final hasSufficientData = displayedSummary.hasSufficientData;
    final analysisSnapshot = const AdvancedAnalysisSnapshotBuilder()
        .fromRunSummary(displayedSummary);

    return Scaffold(
      backgroundColor: _rWhite,
      body: Builder(
        builder: (context) {
          return SafeArea(
            child: Column(
              children: [
                RuniacBackHeader(
                  title: displayedSummary.title,
                  subtitle: displayedSummary.dateTimeLabel,
                  tooltip: 'Back to cool down',
                  scaleTitleToFit: true,
                  onBack: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    }
                  },
                  titleStyle: const TextStyle(
                    color: _rBlue,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                    height: 1.15,
                  ),
                  subtitleStyle: const TextStyle(
                    color: _rBlue60,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                  trailingWidth: 88,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Activity feedback',
                        onPressed: () {
                          // Tier owned by config/featureAccess.activityFeedback
                          // and re-checked inside the activityFeedbackAgent
                          // callable, which is the real gate.
                          if (interceptWithPaywallIfGated(
                            context,
                            'activityFeedback',
                          )) {
                            return;
                          }
                          final character =
                              SelectedRunnerCharacterScope.maybeOf(
                                context,
                              )?.selectedOrDefault ??
                              RunnerCharacter.blue;
                          showDialog<void>(
                            context: context,
                            barrierDismissible: false,
                            barrierColor: Colors.transparent,
                            builder: (dialogContext) {
                              return ActivityFeedbackOverlay(
                                character: character,
                                loadFeedback: () =>
                                    (activityFeedbackAgent ??
                                            CloudFunctionActivityFeedbackAgent())
                                        .explainRun(
                                          ActivityFeedbackRequest(
                                            summary: displayedSummary,
                                            analysis: analysisSnapshot,
                                            cacheIdentity:
                                                _resolvedActivityFeedbackCacheIdentity,
                                          ),
                                        ),
                                onClose: () => Navigator.of(
                                  dialogContext,
                                  rootNavigator: true,
                                ).pop(),
                              );
                            },
                          );
                        },
                        style: IconButton.styleFrom(
                          foregroundColor: _rBlue,
                          minimumSize: const Size(40, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: Image.asset(
                          RuniacAssets.activityFeedbackSparkle,
                          width: 22,
                          height: 22,
                          fit: BoxFit.contain,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Share summary',
                        onPressed: () {
                          // Achievement share-card export: tier owned by
                          // config/featureAccess.shareCards. The card is
                          // rendered and shared on-device, so this client
                          // gate is the whole enforcement.
                          if (interceptWithPaywallIfGated(
                            context,
                            'shareCards',
                          )) {
                            return;
                          }
                          Future<FeedThumbnailArtifact?>? mapArtifactFuture;
                          if (displayedSummary.route.hasRoute) {
                            final source = _effectiveFeedPublishSource;
                            final thumbnailIdentity =
                                source.cacheIdentity ??
                                source.activityId ??
                                'local-summary-preview';
                            mapArtifactFuture =
                                _generateRouteThumbnailArtifact(
                                      summary: displayedSummary,
                                      thumbnailIdentity: thumbnailIdentity,
                                      devicePixelRatio:
                                          MediaQuery.devicePixelRatioOf(
                                            context,
                                          ),
                                    )
                                    .then<FeedThumbnailArtifact?>(
                                      (artifact) => artifact,
                                    )
                                    .catchError((_) => null);
                          }
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            backgroundColor: Colors.transparent,
                            barrierColor: Colors.black.withValues(alpha: 0.48),
                            builder: (context) => ShareAchievementSheet(
                              summary: displayedSummary,
                              mapArtifact: mapArtifactFuture,
                            ),
                          );
                        },
                        style: IconButton.styleFrom(
                          foregroundColor: _rBlue,
                          minimumSize: const Size(40, 40),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.share_outlined, size: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: const _NoOverscrollBehavior(),
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SourceLabel(
                            sourceLabel: displayedSummary.sourceLabel,
                          ),
                          _MapPreview(
                            routeName: displayedSummary.routeName,
                            route: displayedSummary.route,
                            mapboxAccessToken: mapboxAccessToken,
                            mapboxBuilder: mapboxBuilder,
                          ),
                          _HeroDistance(
                            distanceKm: displayedSummary.distanceKm,
                          ),
                          _MetricSummary(summary: displayedSummary),
                          _PaceSection(
                            hasSufficientData: hasSufficientData,
                            paceGraph: displayedSummary.paceGraph,
                          ),
                          _AnalysisSection(
                            hasSufficientData: hasSufficientData,
                            paceAnalysis: analysisSnapshot.pace,
                            onMoreDetails: () {
                              if (!hasSufficientData) {
                                _showSoonMessage(
                                  context,
                                  'Run a little longer to unlock analysis.',
                                );
                                return;
                              }
                              // Tier owned by
                              // config/featureAccess.advancedAnalysis. The
                              // analysis is computed on-device, so there is no
                              // server call to back this gate up.
                              if (interceptWithPaywallIfGated(
                                context,
                                'advancedAnalysis',
                              )) {
                                return;
                              }

                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (context) => AdvancedAnalysisScreen(
                                    title: displayedSummary.title,
                                    subtitle: displayedSummary.dateTimeLabel,
                                    analysisSnapshot: analysisSnapshot,
                                  ),
                                ),
                              );
                            },
                          ),
                          _CoachingSection(
                            coachingSummary: displayedSummary.coachingSummary,
                            // Post-run coaching insight is part of the
                            // Advanced-analysis surface, so it follows the
                            // same admin-owned tier rather than a hardcoded
                            // lock.
                            premiumLocked: watchShouldShowPaywallForFeature(
                              context,
                              'advancedAnalysis',
                            ),
                            onLockedTap: () =>
                                PremiumPaywallSheet.show(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                _BottomActions(
                  hasSufficientData: hasSufficientData,
                  showXpUpdateAction: showXpUpdateAction,
                  showLowDataSaveAction: showLowDataSaveAction,
                  onShareRoute: () {
                    // Tier owned by config/featureAccess.shareRouteToFeed and
                    // re-checked inside publishActivityToFeed, which is the
                    // real gate. Intercepting here is UX only — and it now
                    // stands down when the admin sets the feature to Basic,
                    // instead of paywalling every Basic runner regardless.
                    if (interceptWithPaywallIfGated(
                      context,
                      'shareRouteToFeed',
                    )) {
                      return;
                    }
                    _showShareRouteToFeed(context, displayedSummary);
                  },
                  onXpUpdate: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (context) => XpUpdateScreen(
                          model:
                              completionResult?.xpUpdate ??
                              defaultXpUpdateDisplayModel,
                        ),
                      ),
                    );
                  },
                  onGoHome: () {
                    _goHomeFromSummary(
                      context,
                      hasSufficientData: hasSufficientData,
                    );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String? get _resolvedActivityFeedbackCacheIdentity {
    final result = completionResult;
    for (final identity in <String?>[
      activityFeedbackCacheIdentity,
      result?.activityId,
      result?.clientRunSessionId,
      result?.summaryId,
    ]) {
      final normalized = identity?.trim();
      if (normalized != null && normalized.isNotEmpty) return normalized;
    }
    return null;
  }
}
