import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/widgets/runiac_avatar_photo.dart';
import 'package:runiac_app/core/widgets/runiac_level_profile_badge.dart';

void main() {
  const badgeSize = 96.0;
  const strokeWidth = 8.0;
  const startAngle = math.pi * 5 / 6;
  const gaugeSweep = math.pi * 4 / 3;
  const ringRect = Rect.fromLTWH(
    strokeWidth / 2,
    strokeWidth / 2,
    badgeSize - strokeWidth,
    badgeSize - strokeWidth,
  );

  Future<void> pumpBadge(
    WidgetTester tester, {
    required double progressFraction,
    String levelLabel = 'Lv.1',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: RuniacLevelProfileBadge(
              initials: 'B',
              levelLabel: levelLabel,
              progressFraction: progressFraction,
              size: badgeSize,
              ringStrokeWidth: strokeWidth,
            ),
          ),
        ),
      ),
    );
  }

  Finder findBadgeRing() {
    return find.descendant(
      of: find.byType(RuniacLevelProfileBadge),
      matching: find.byType(CustomPaint),
    );
  }

  testWidgets('XP ring paints a bottom-open 240 degree gauge track', (
    WidgetTester tester,
  ) async {
    await pumpBadge(tester, progressFraction: 0);

    expect(findBadgeRing(), paintsExactlyCountTimes(#drawArc, 1));
    expect(
      findBadgeRing(),
      paints..arc(
        rect: ringRect,
        startAngle: startAngle,
        sweepAngle: gaugeSweep,
        useCenter: false,
        strokeWidth: strokeWidth,
        style: PaintingStyle.stroke,
        strokeCap: StrokeCap.round,
      ),
    );
  });

  testWidgets('XP ring maps fifty percent to half of the visible gauge', (
    WidgetTester tester,
  ) async {
    await pumpBadge(tester, progressFraction: 0.5);

    expect(findBadgeRing(), paintsExactlyCountTimes(#drawArc, 2));
    expect(
      findBadgeRing(),
      paints
        ..arc(
          rect: ringRect,
          startAngle: startAngle,
          sweepAngle: gaugeSweep,
          useCenter: false,
          strokeWidth: strokeWidth,
          style: PaintingStyle.stroke,
          strokeCap: StrokeCap.round,
        )
        ..arc(
          rect: ringRect,
          startAngle: startAngle,
          sweepAngle: gaugeSweep * 0.5,
          useCenter: false,
          strokeWidth: strokeWidth,
          style: PaintingStyle.stroke,
          strokeCap: StrokeCap.round,
        ),
    );
  });

  testWidgets('XP ring clamps overfilled progress to the visible gauge', (
    WidgetTester tester,
  ) async {
    await pumpBadge(tester, progressFraction: 1.4, levelLabel: 'Lv.100');

    expect(find.text('Lv.100'), findsOneWidget);
    expect(findBadgeRing(), paintsExactlyCountTimes(#drawArc, 2));
    expect(
      findBadgeRing(),
      paints
        ..arc(
          rect: ringRect,
          startAngle: startAngle,
          sweepAngle: gaugeSweep,
          useCenter: false,
          strokeWidth: strokeWidth,
          style: PaintingStyle.stroke,
          strokeCap: StrokeCap.round,
        )
        ..arc(
          rect: ringRect,
          startAngle: startAngle,
          sweepAngle: gaugeSweep,
          useCenter: false,
          strokeWidth: strokeWidth,
          style: PaintingStyle.stroke,
          strokeCap: StrokeCap.round,
        ),
    );
  });

  testWidgets('compact two-letter initials stay centered inside the disc', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: RuniacLevelProfileBadge(
              initials: 'AR',
              levelLabel: 'Lv.12',
              progressFraction: 0,
              size: 42,
              badgeHeight: 16,
              badgeMinWidth: 42,
              badgeHorizontalPadding: 6,
              badgeFontSize: 9,
              ringStrokeWidth: 4,
            ),
          ),
        ),
      ),
    );

    final initials = tester.widget<Text>(find.text('AR'));
    expect(initials.textAlign, TextAlign.center);
    expect(
      find.ancestor(of: find.text('AR'), matching: find.byType(FittedBox)),
      findsOneWidget,
    );
  });

  group('avatar photo rendering', () {
    const testBucket = 'test-avatars-bucket.appspot.com';
    const validObjectId = '0123456789abcdef0123456789abcdef';
    const validToken = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
    const wellFormedPhotoUrl =
        'https://firebasestorage.googleapis.com/v0/b/$testBucket/o/'
        'avatars%2F$validObjectId.png?alt=media&token=$validToken';

    late String Function() originalBucketResolver;
    late ImageProvider Function(String url) originalImageProviderFactory;

    setUp(() {
      originalBucketResolver = avatarStorageBucketResolver;
      originalImageProviderFactory = avatarImageProviderFactory;
      avatarStorageBucketResolver = () => testBucket;
    });

    tearDown(() {
      avatarStorageBucketResolver = originalBucketResolver;
      avatarImageProviderFactory = originalImageProviderFactory;
    });

    testWidgets(
      'renders the photo and hides the initials when a sanitised URL '
      'resolves through a successful provider',
      (WidgetTester tester) async {
        // Runs the pump under runAsync: a real (test-decoded) ui.Image needs
        // a real async raster turn to composite, which the fake-async zone
        // WidgetTester normally pumps under never advances on its own.
        await tester.runAsync(() async {
          final image = await createTestImage();
          avatarImageProviderFactory = (url) =>
              _FakeSuccessImageProvider(image);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: RuniacLevelProfileBadge(
                    initials: 'AR',
                    levelLabel: 'Lv.12',
                    progressFraction: 0,
                    size: badgeSize,
                    ringStrokeWidth: strokeWidth,
                    photoUrl: wellFormedPhotoUrl,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        });

        expect(find.text('AR'), findsNothing);
        expect(find.byType(Image), findsOneWidget);
      },
    );

    testWidgets(
      'falls back to the initials when the image provider fails to load',
      (WidgetTester tester) async {
        avatarImageProviderFactory = (url) => const _FakeFailureImageProvider();

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RuniacLevelProfileBadge(
                  initials: 'AR',
                  levelLabel: 'Lv.12',
                  progressFraction: 0,
                  size: badgeSize,
                  ringStrokeWidth: strokeWidth,
                  photoUrl: wellFormedPhotoUrl,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('AR'), findsOneWidget);
      },
    );

    testWidgets(
      'keeps painting exactly one ring arc-pass with a photo present',
      (WidgetTester tester) async {
        await tester.runAsync(() async {
          final image = await createTestImage();
          avatarImageProviderFactory = (url) =>
              _FakeSuccessImageProvider(image);

          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: RuniacLevelProfileBadge(
                    initials: 'B',
                    levelLabel: 'Lv.1',
                    progressFraction: 0,
                    size: badgeSize,
                    ringStrokeWidth: strokeWidth,
                    photoUrl: wellFormedPhotoUrl,
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
        });

        expect(findBadgeRing(), paintsExactlyCountTimes(#drawArc, 1));
        expect(findBadgeRing(), findsOneWidget);
      },
    );

    testWidgets('.row constructor accepts and renders a photo too', (
      WidgetTester tester,
    ) async {
      await tester.runAsync(() async {
        final image = await createTestImage();
        avatarImageProviderFactory = (url) => _FakeSuccessImageProvider(image);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: RuniacLevelProfileBadge.row(
                  initials: 'AR',
                  levelLabel: 'Lv.12',
                  progressFraction: 0,
                  photoUrl: wellFormedPhotoUrl,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      });

      expect(find.text('AR'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}

/// A synchronous, non-network [ImageProvider] test double that always
/// resolves to [image]. Used to test the photo-renders success path without
/// depending on real network access, which `flutter_test` never has.
class _FakeSuccessImageProvider extends ImageProvider<_FakeSuccessImageProvider> {
  const _FakeSuccessImageProvider(this.image);

  final ui.Image image;

  @override
  Future<_FakeSuccessImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_FakeSuccessImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _FakeSuccessImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.value(ImageInfo(image: image)),
    );
  }
}

/// A synchronous, non-network [ImageProvider] test double that always fails
/// to load. Used to test the errorBuilder fallback deterministically,
/// without depending on real (and, in this sandbox, hanging) network access.
class _FakeFailureImageProvider
    extends ImageProvider<_FakeFailureImageProvider> {
  const _FakeFailureImageProvider();

  @override
  Future<_FakeFailureImageProvider> obtainKey(
    ImageConfiguration configuration,
  ) {
    return SynchronousFuture<_FakeFailureImageProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    _FakeFailureImageProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(
      Future<ImageInfo>.error(
        Exception('Simulated avatar photo load failure'),
      ),
    );
  }
}
