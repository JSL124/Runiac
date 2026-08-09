import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../../run/domain/models/run_activity_display_model.dart';
import '../../../run/presentation/widgets/mapbox_runtime_config.dart';
import 'activity_route_mapbox_snapshot_provider.dart';
import 'activity_route_preview.dart';
import 'activity_route_snapshot_thumbnail_cache.dart';

/// One run as a row in the activity history: route thumbnail, date, and the
/// headline metrics.
///
/// The thumbnail is resolved through the shared snapshot cache rather than
/// rendered per card — a scrolling history would otherwise start a Mapbox
/// snapshot per row. When no Mapbox token is configured the card falls back to
/// the painted route preview, so the history looks complete offline.
class CompactRunActivityCard extends StatelessWidget {
  const CompactRunActivityCard({
    required this.activity,
    required this.onTap,
    this.routeThumbnailProvider,
    super.key,
  });

  final RunActivityDisplayModel activity;
  final VoidCallback onTap;
  final ActivityRouteThumbnailProvider? routeThumbnailProvider;

  @override
  Widget build(BuildContext context) {
    final isCurrentSessionRoute = activity.completionResult != null;
    final allowsTrustedRoutePreviewThumbnail =
        isCurrentSessionRoute || activity.isTrustedPersistedRoutePreview;
    return RuniacTappableSurface(
      onTap: onTap,
      semanticLabel: 'Open ${activity.title} summary',
      borderRadius: BorderRadius.circular(20),
      constraints: const BoxConstraints(minHeight: 114),
      padding: const EdgeInsets.all(12),
      decoration: _historyCardDecoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ActivityRoutePreview(
            route: activity.summary.route,
            thumbnailProvider:
                routeThumbnailProvider ?? _activityRouteThumbnailProvider,
            allowExternalStaticMap: allowsTrustedRoutePreviewThumbnail,
            isCurrentSessionRoute: isCurrentSessionRoute,
            isTrustedPersistedRoutePreview:
                activity.isTrustedPersistedRoutePreview,
            activityId: activity.identityKey,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: _ActivityCardContent(
              key: const ValueKey('activity_card_content'),
              activity: activity,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityCardContent extends StatelessWidget {
  const _ActivityCardContent({required this.activity, super.key});

  final RunActivityDisplayModel activity;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 19,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(activity.title, maxLines: 1, style: _cardTitleStyle),
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(activity.timeAgoLabel, style: _cardDateStyle),
            Text(activity.sourceLabel, style: _cardSourceStyle),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _Metric(value: activity.distanceLabel, label: 'Distance'),
            ),
            const _MetricDivider(),
            Expanded(
              child: _Metric(value: activity.paceLabel, label: 'Avg Pace'),
            ),
            const _MetricDivider(),
            Expanded(
              child: _Metric(value: activity.durationLabel, label: 'Time'),
            ),
          ],
        ),
      ],
    );
  }
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 34,
      child: VerticalDivider(width: 18, thickness: 1, color: Color(0xFFDDE5FA)),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final distanceParts = label == 'Distance' && value.endsWith(' km')
        ? value.split(' ')
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (distanceParts == null)
          _MetricValueText(child: Text(value, style: _metricValueStyle))
        else
          _MetricValueText(
            child: Text.rich(
              TextSpan(
                text: distanceParts.first,
                style: _metricValueStyle,
                children: const [
                  TextSpan(text: ' km', style: _metricUnitStyle),
                ],
              ),
            ),
          ),
        const SizedBox(height: 2),
        Text(label.toUpperCase(), style: _metricLabelStyle),
      ],
    );
  }
}

class _MetricValueText extends StatelessWidget {
  const _MetricValueText({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}

final _historyCardDecoration = BoxDecoration(
  color: RuniacColors.white,
  borderRadius: BorderRadius.circular(24),
  border: Border.all(color: RuniacColors.cardBorder, width: 1.1),
  boxShadow: const [
    BoxShadow(
      color: RuniacColors.softCardShadow,
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
  ],
);

const _cardTitleStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 17,
  fontWeight: FontWeight.w900,
  height: 1.1,
);
const _cardDateStyle = TextStyle(
  color: Color(0xFF7D93E1),
  fontSize: 13,
  fontWeight: FontWeight.w700,
);
const _cardSourceStyle = TextStyle(
  color: RuniacColors.primaryBlue,
  fontSize: 12,
  fontWeight: FontWeight.w800,
);
const _metricValueStyle = TextStyle(
  color: RuniacColors.textPrimary,
  fontSize: 17,
  fontWeight: FontWeight.w900,
  height: 1,
);
const _metricUnitStyle = TextStyle(
  color: Color(0xFFA4B3EA),
  fontSize: 11,
  fontWeight: FontWeight.w800,
);
const _metricLabelStyle = TextStyle(
  color: Color(0xFFA4B3EA),
  fontSize: 10,
  fontWeight: FontWeight.w800,
);

final _activityRouteThumbnailCache =
    ActivityRouteSnapshotThumbnailMemoryCache();
final _activityRouteThumbnailProvider = _createActivityRouteThumbnailProvider();

ActivityRouteThumbnailProvider _createActivityRouteThumbnailProvider() {
  final config = MapboxRuntimeConfig.fromEnvironment();
  return CachedActivityRouteThumbnailProvider(
    cache: _activityRouteThumbnailCache,
    generator: MapboxActivityRouteSnapshotThumbnailGenerator(
      accessToken: config.accessToken,
      onDiagnostic: _logActivityRouteSnapshotterDiagnostic,
    ),
    snapshotThumbnailsEnabled: config.snapshotThumbnailsEnabled,
    hasValidMapboxToken: config.hasPublicAccessToken,
    onDiagnostic: _logActivityRouteThumbnailDiagnostic,
  );
}

void _logActivityRouteSnapshotterDiagnostic(
  ActivityRouteSnapshotterDiagnostic diagnostic,
) {
  if (!_activityRouteThumbnailDiagnosticsEnabled) {
    return;
  }
  final state = diagnostic.state;
  final byteLength = diagnostic.byteLength;
  final errorType = diagnostic.errorType;
  final errorDescription = diagnostic.errorDescription;
  debugPrint(
    'Runiac Activity route snapshotter: '
    'activityId=${diagnostic.activityId ?? "(none)"} '
    'event=${diagnostic.event.name} '
    'state=${state?.name ?? "(pending)"} '
    'bytes=${byteLength?.toString() ?? "(unknown)"} '
    'style=${diagnostic.styleUri} '
    'size=${diagnostic.logicalSize.width.toStringAsFixed(0)}x'
    '${diagnostic.logicalSize.height.toStringAsFixed(0)} '
    'dpr=${diagnostic.devicePixelRatio.toStringAsFixed(2)} '
    // Masked to three decimals (~110m). This is deliberately coarser than the
    // five decimals a route preview persists
    // (`RunCompletionRequestPayloadSerializer._quantizeCoordinate`): the stored
    // preview has to draw an accurate line, whereas a debug log only needs to
    // confirm the camera landed on the right route, so it has no reason to
    // pinpoint where the runner actually was.
    'center=${diagnostic.centerLatitude.toStringAsFixed(3)},'
    '${diagnostic.centerLongitude.toStringAsFixed(3)} '
    'zoom=${diagnostic.zoom.toStringAsFixed(2)} '
    'errorType=${errorType ?? "(none)"} '
    'error=${errorDescription ?? "(none)"}',
  );
}

void _logActivityRouteThumbnailDiagnostic(
  ActivityRouteThumbnailDiagnostic diagnostic,
) {
  if (!_activityRouteThumbnailDiagnosticsEnabled) {
    return;
  }
  debugPrint(
    'Runiac Activity route thumbnail: '
    'activityId=${diagnostic.activityId ?? "(none)"} '
    'state=${diagnostic.fallbackReason} '
    'source=${diagnostic.source.name} '
    'allowExternal=${diagnostic.allowExternalStaticMap} '
    'demo=${diagnostic.isDemoRoute} '
    'currentSession=${diagnostic.isCurrentSessionRoute} '
    'trustedPersistedPreview=${diagnostic.isTrustedPersistedRoutePreview} '
    'snapshotFlag=${diagnostic.snapshotThumbnailsEnabled} '
    'publicToken=${diagnostic.hasValidMapboxToken} '
    'knownLocation=${diagnostic.hasKnownLocation}',
  );
}

const _activityRouteThumbnailDiagnosticsEnabled = bool.fromEnvironment(
  'RUNIAC_ENABLE_MAPBOX_SNAPSHOT_DIAGNOSTICS',
);
