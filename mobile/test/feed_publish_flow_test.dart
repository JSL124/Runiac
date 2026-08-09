import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:runiac_app/features/feed/data/feed_publish/feed_publish_service.dart';
import 'package:runiac_app/features/feed/data/feed_publish/feed_thumbnail_artifact.dart';
import 'package:runiac_app/features/feed/data/feed_publish/firebase_feed_publish_gateway.dart';
import 'package:runiac_app/features/feed/data/feed_publish/history_artifact_resolver.dart';
import 'package:runiac_app/features/feed/domain/models/feed_display_models.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_preview.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_snapshot_thumbnail_cache.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/presentation/data/run_completion_demo_snapshots.dart';
import 'package:runiac_app/features/run/presentation/widgets/share_route_to_feed_sheet.dart';

const _shareSheetAuthorProfile = FeedAuthorProfileSnapshot(
  userId: 'runner-current',
  displayName: 'You',
  avatarInitials: 'YO',
  levelLabel: 'Level 6',
  levelProgressFraction: 0.42,
);

void main() {
  test(
    'publish is dormant until an explicit confirmation and reuses PNG bytes',
    () async {
      final gateway = _FakeGateway();
      final service = FeedPublishService(gateway: gateway);
      final bytes = Uint8List.fromList(const <int>[137, 80, 78, 71]);
      final artifact = FeedThumbnailArtifact(bytes);

      expect(gateway.stageCalls, 0);
      expect(gateway.publishCalls, 0);

      final first = service.publishAfterConfirmation(
        activityId: 'activity-a',
        artifact: artifact,
      );
      final second = service.publishAfterConfirmation(
        activityId: 'activity-a',
        artifact: artifact,
      );
      final result = await first;

      expect(await second, same(result));
      expect(gateway.stageCalls, 1);
      expect(gateway.publishCalls, 1);
      expect(gateway.stagedBytes, same(bytes));
      expect(result.postId, 'activity-a');
    },
  );

  test('staging descriptor uses filename metadata required by rules', () {
    final bytes = Uint8List.fromList(const <int>[1, 2, 3]);
    final upload = FeedStagingUpload.create(
      ownerUid: 'owner',
      activityId: 'activity',
      bytes: bytes,
      token: 'token',
    );
    expect(upload.path, 'feed-thumbnail-staging/owner/activity/token.png');
    expect(upload.metadata, <String, String>{
      'ownerUid': 'owner',
      'activityId': 'activity',
      'uploadId': 'token.png',
    });
    expect(upload.bytes, same(bytes));
  });

  test(
    'History client-session artifact reaches MemoryImage and staging by identity',
    () async {
      final bytes = _fixturePng();
      final request = ActivityRouteThumbnailRequest(
        route: RunRouteSnapshot.empty,
        logicalSize: const Size(88, 88),
        devicePixelRatio: 1,
        allowExternalStaticMap: true,
        isDemoRoute: true,
        activityId: 'client-session-id',
      );
      final cache = ActivityRouteSnapshotThumbnailMemoryCache();
      cache.store(
        ActivityRouteSnapshotThumbnailCacheKey.fromRequest(request),
        ActivityRouteThumbnailResult.readyPng(bytes),
        ownerUid: 'owner-a',
      );
      final resolver = CacheOnlyHistoryArtifactResolver(
        cache: ActivityRouteSnapshotThumbnailMemoryCache(),
        ownerUidProvider: () => 'owner-a',
      );
      final artifact = await resolver.resolve(request);
      final gateway = _FakeGateway();
      await FeedPublishService(gateway: gateway).publishAfterConfirmation(
        activityId: 'activity-id',
        artifact: artifact!,
      );
      expect((artifact.memoryImage).bytes, same(bytes));
      expect(gateway.stagedBytes, same(bytes));
    },
  );

  test('cache-only resolver miss and owner B cause zero staging', () async {
    final request = ActivityRouteThumbnailRequest(
      route: RunRouteSnapshot.empty,
      logicalSize: const Size(88, 88),
      devicePixelRatio: 1,
      allowExternalStaticMap: true,
      isDemoRoute: true,
      activityId: 'client-session-id',
    );
    final cache = ActivityRouteSnapshotThumbnailMemoryCache();
    cache.store(
      ActivityRouteSnapshotThumbnailCacheKey.fromRequest(request),
      ActivityRouteThumbnailResult.readyPng(_fixturePng()),
      ownerUid: 'owner-a',
    );
    final artifact = await CacheOnlyHistoryArtifactResolver(
      cache: ActivityRouteSnapshotThumbnailMemoryCache(),
      ownerUidProvider: () => 'owner-b',
    ).resolve(request);
    expect(artifact, isNull);
  });

  testWidgets(
    'share sheet disables posting without the exact History artifact',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareRouteToFeedSheet(
              summary: defaultRunSummarySnapshot,
              authorProfile: _shareSheetAuthorProfile,
              onCancel: () {},
              onConfirm: () async {
                calls += 1;
              },
            ),
          ),
        ),
      );
      expect(
        find.text(
          'Your private route preview is unavailable. Your run is still saved.',
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.widgetWithText(FilledButton, 'Post to Feed'),
      );
      await tester.pump();
      await tester.tap(find.text('Post to Feed'));
      expect(calls, 0);
    },
  );

  testWidgets('share sheet renders the exact artifact MemoryImage', (
    tester,
  ) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL5WQAAAABJRU5ErkJggg==',
    );
    final artifact = FeedThumbnailArtifact(bytes);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareRouteToFeedSheet(
            summary: defaultRunSummarySnapshot,
            artifact: artifact,
            authorProfile: _shareSheetAuthorProfile,
            onCancel: () {},
            onConfirm: () async {},
          ),
        ),
      ),
    );
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as MemoryImage).bytes, same(artifact.pngBytes));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('share sheet preserves publish rejection messages', (
    tester,
  ) async {
    final artifact = FeedThumbnailArtifact(_fixturePng());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareRouteToFeedSheet(
            summary: defaultRunSummarySnapshot,
            artifact: artifact,
            authorProfile: _shareSheetAuthorProfile,
            onCancel: () {},
            onConfirm: () async {
              throw const FeedPublishException(
                'Activity is not publishable yet.',
              );
            },
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Post to Feed'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Post to Feed'));
    await tester.pump();

    expect(find.text('Activity is not publishable yet.'), findsOneWidget);
  });

  testWidgets('share sheet exposes unexpected posting failures', (
    tester,
  ) async {
    final artifact = FeedThumbnailArtifact(_fixturePng());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareRouteToFeedSheet(
            summary: defaultRunSummarySnapshot,
            artifact: artifact,
            authorProfile: _shareSheetAuthorProfile,
            onCancel: () {},
            onConfirm: () async {
              throw Exception('Firebase Storage bucket is not configured');
            },
          ),
        ),
      ),
    );

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Post to Feed'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Post to Feed'));
    await tester.pump();

    expect(
      find.textContaining('Firebase Storage bucket is not configured'),
      findsOneWidget,
    );
  });

  testWidgets('share sheet disables posting when source is unavailable', (
    tester,
  ) async {
    final artifact = FeedThumbnailArtifact(_fixturePng());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareRouteToFeedSheet(
            summary: defaultRunSummarySnapshot,
            artifact: artifact,
            postingUnavailableMessage: 'This run is still being validated.',
            authorProfile: _shareSheetAuthorProfile,
            onCancel: () {},
            onConfirm: () async {},
          ),
        ),
      ),
    );

    expect(find.text('This run is still being validated.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });

  test('a staging failure is recoverable and never calls publish', () async {
    final gateway = _FakeGateway(stageError: StateError('unavailable'));
    final service = FeedPublishService(gateway: gateway);

    await expectLater(
      service.publishAfterConfirmation(
        activityId: 'activity-a',
        artifact: FeedThumbnailArtifact(Uint8List.fromList(const <int>[1])),
      ),
      throwsA(
        isA<FeedPublishException>().having(
          (error) => error.message,
          'message',
          contains('Bad state: unavailable'),
        ),
      ),
    );

    expect(gateway.publishCalls, 0);
  });

  test('a publish failure keeps the backend error visible', () async {
    final gateway = _FakeGateway(publishError: StateError('profile missing'));
    final service = FeedPublishService(gateway: gateway);

    await expectLater(
      service.publishAfterConfirmation(
        activityId: 'activity-a',
        artifact: FeedThumbnailArtifact(Uint8List.fromList(const <int>[1])),
      ),
      throwsA(
        isA<FeedPublishException>().having(
          (error) => error.message,
          'message',
          contains('Bad state: profile missing'),
        ),
      ),
    );

    expect(gateway.stageCalls, 1);
    expect(gateway.publishCalls, 1);
  });

  test(
    'a hung staging request is recoverable and never calls publish',
    () async {
      final gateway = _FakeGateway(neverStage: true);
      final service = FeedPublishService(
        gateway: gateway,
        operationTimeout: const Duration(milliseconds: 1),
      );

      await expectLater(
        service.publishAfterConfirmation(
          activityId: 'activity-a',
          artifact: FeedThumbnailArtifact(Uint8List.fromList(const <int>[1])),
        ),
        throwsA(
          isA<FeedPublishException>().having(
            (error) => error.message,
            'message',
            contains('Posting timed out'),
          ),
        ),
      );

      expect(gateway.publishCalls, 0);
    },
  );
}

class _FakeGateway implements FeedPublishGateway {
  _FakeGateway({this.stageError, this.publishError, this.neverStage = false});

  final Object? stageError;
  final Object? publishError;
  final bool neverStage;
  int stageCalls = 0;
  int publishCalls = 0;
  Uint8List? stagedBytes;

  @override
  Future<FeedPublishResponse> publish({
    required String activityId,
    required String stagingPath,
  }) async {
    publishCalls += 1;
    if (publishError != null) throw publishError!;
    return FeedPublishResponse(postId: activityId);
  }

  @override
  Future<String> stage({
    required String activityId,
    required Uint8List pngBytes,
  }) async {
    stageCalls += 1;
    stagedBytes = pngBytes;
    if (neverStage) return Completer<String>().future;
    if (stageError != null) throw stageError!;
    return 'feed-thumbnail-staging/owner/$activityId/upload.png';
  }
}

Uint8List _fixturePng() {
  final output = <int>[137, 80, 78, 71, 13, 10, 26, 10];
  void chunk(String type, List<int> data) {
    final length = data.length;
    output.addAll(<int>[length >> 24, length >> 16, length >> 8, length]);
    final typeBytes = type.codeUnits;
    output.addAll(typeBytes);
    output.addAll(data);
    final crc = _crc(<int>[...typeBytes, ...data]);
    output.addAll(<int>[crc >> 24, crc >> 16, crc >> 8, crc]);
  }

  chunk('IHDR', <int>[0, 0, 0, 88, 0, 0, 0, 88, 8, 6, 0, 0, 0]);
  chunk('IDAT', const <int>[0]);
  chunk('IEND', const <int>[]);
  return Uint8List.fromList(output);
}

int _crc(List<int> values) {
  var crc = 0xffffffff;
  for (final value in values) {
    crc ^= value;
    for (var bit = 0; bit < 8; bit += 1) {
      crc = (crc & 1) == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320;
    }
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
