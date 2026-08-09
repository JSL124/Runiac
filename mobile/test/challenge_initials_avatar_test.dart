import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/widgets/runiac_avatar_photo.dart';
import 'package:runiac_app/features/challenge/presentation/widgets/challenge_widgets.dart';

void main() {
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

  testWidgets('renders only initials when no photo URL is supplied', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: ChallengeInitialsAvatar(initials: 'JS')),
        ),
      ),
    );

    expect(find.text('JS'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'renders the photo and hides the initials when a sanitised URL '
    'resolves through a successful provider',
    (WidgetTester tester) async {
      // Runs the pump under runAsync: a real (test-decoded) ui.Image needs a
      // real async raster turn to composite, which the fake-async zone
      // WidgetTester normally pumps under never advances on its own.
      await tester.runAsync(() async {
        final image = await createTestImage();
        avatarImageProviderFactory = (url) => _FakeSuccessImageProvider(image);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: ChallengeInitialsAvatar(
                  initials: 'JS',
                  photoUrl: wellFormedPhotoUrl,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      });

      expect(find.text('JS'), findsNothing);
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
              child: ChallengeInitialsAvatar(
                initials: 'JS',
                photoUrl: wellFormedPhotoUrl,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('JS'), findsOneWidget);
    },
  );

  testWidgets('falls back to the initials when the URL fails sanitisation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: ChallengeInitialsAvatar(
              initials: 'JS',
              photoUrl: 'https://evil.example.com/not-an-avatar.png',
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('JS'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}

/// A synchronous, non-network [ImageProvider] test double that always
/// resolves to [image]. Used to test the photo-renders success path without
/// depending on real network access, which `flutter_test` never has.
class _FakeSuccessImageProvider
    extends ImageProvider<_FakeSuccessImageProvider> {
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
