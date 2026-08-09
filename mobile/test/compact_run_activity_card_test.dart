import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/run_activity_display_model.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';
import 'package:runiac_app/features/you/presentation/widgets/compact_run_activity_card.dart';

void main() {
  testWidgets('long generated run title stays fully visible in the card', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: CompactRunActivityCard(
              activity: _activity(
                isTrustedPersistedRoutePreview: false,
                title: 'Wednesday Afternoon Run',
              ),
              onTap: () {},
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Wednesday Afternoon Run'));
    expect(title.overflow, isNot(TextOverflow.ellipsis));
    expect(
      find.ancestor(
        of: find.text('Wednesday Afternoon Run'),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'trusted persisted route preview requests thumbnail without current completion',
    (WidgetTester tester) async {
      // Given: a signed-in Firestore projection with an explicitly trusted
      // persisted preview and no current-session completion result after reinstall.
      final provider = _RecordingThumbnailProvider();
      final activity = _activity(isTrustedPersistedRoutePreview: true);
      expect(activity.completionResult, isNull);

      // When: the History card renders the persisted route preview.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompactRunActivityCard(
              activity: activity,
              routeThumbnailProvider: provider,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Then: the card authorizes the existing guarded thumbnail boundary
      // without mislabeling persisted provenance as a current-session route.
      expect(provider.requests, hasLength(1));
      expect(provider.requests.single.allowExternalStaticMap, isTrue);
      expect(provider.requests.single.isCurrentSessionRoute, isFalse);
      expect(provider.requests.single.isTrustedPersistedRoutePreview, isTrue);
      expect(provider.requests.single.isDemoRoute, isFalse);
      expect(provider.requests.single.activityId, 'persisted-route-session');
    },
  );

  testWidgets(
    'untrusted persisted route preview keeps thumbnail privacy disabled',
    (WidgetTester tester) async {
      // Given: the same route geometry without trusted authenticated provenance.
      final provider = _RecordingThumbnailProvider();
      final activity = _activity(isTrustedPersistedRoutePreview: false);

      // When: the History card renders the untrusted row.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CompactRunActivityCard(
              activity: activity,
              routeThumbnailProvider: provider,
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Then: route geometry is never authorized for an external static map.
      expect(provider.requests, hasLength(1));
      expect(provider.requests.single.allowExternalStaticMap, isFalse);
      expect(provider.requests.single.isCurrentSessionRoute, isFalse);
      expect(provider.requests.single.isTrustedPersistedRoutePreview, isFalse);
      expect(provider.requests.single.isDemoRoute, isFalse);
    },
  );
}

RunActivityDisplayModel _activity({
  required bool isTrustedPersistedRoutePreview,
  String title = 'Persisted route preview run',
}) {
  final summary = RunSummarySnapshot(
    title: title,
    dateLabel: '14/6/26',
    timeLabel: '7:25 AM',
    distanceKm: '3.20',
    avgPace: '7’49”',
    duration: '25:00',
    avgHeartRate: '--',
    calories: '--',
    routeName: 'Private route',
    route: RunRouteSnapshot(
      segments: <List<RunLocationSample>>[
        <RunLocationSample>[
          RunLocationSample(
            recordedAt: DateTime.utc(2026, 6, 14, 7, 25),
            latitude: 1.301,
            longitude: 103.801,
          ),
          RunLocationSample(
            recordedAt: DateTime.utc(2026, 6, 14, 7, 25, 30),
            latitude: 1.302,
            longitude: 103.802,
          ),
        ],
      ],
      lastKnownLocation: RunLocationSample(
        recordedAt: DateTime.utc(2026, 6, 14, 7, 25, 30),
        latitude: 1.302,
        longitude: 103.802,
      ),
    ),
  );
  return RunActivityDisplayModel(
    activityId: 'persisted-route-activity',
    clientRunSessionId: 'persisted-route-session',
    title: summary.title,
    timeAgoLabel: summary.dateLabel,
    distanceLabel: '${summary.distanceKm} km',
    distanceMeters: 3200,
    paceLabel: summary.avgPace,
    durationLabel: summary.duration,
    summary: summary,
    isTrustedPersistedRoutePreview: isTrustedPersistedRoutePreview,
  );
}

class _RecordingThumbnailProvider implements ActivityRouteThumbnailProvider {
  final requests = <ActivityRouteThumbnailRequest>[];

  @override
  Future<ActivityRouteThumbnailResult> resolve(
    ActivityRouteThumbnailRequest request,
  ) async {
    requests.add(request);
    return const ActivityRouteThumbnailResult.unavailable();
  }
}
