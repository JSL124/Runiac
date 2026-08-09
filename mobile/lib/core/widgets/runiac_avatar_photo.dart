import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../../features/run/data/run_repository_factory.dart'
    show RuniacFirebaseRuntimeConfig;

// Dart mirror of `functions/src/profile/avatar/avatarPaths.ts`
// `resolveProfileAvatarUrl`. This is defence-in-depth, not the primary
// guard: every `avatarUrl` value this app ever sees was already sanitised
// server-side by that TypeScript function before it was written to
// `userProfiles/{uid}` or relayed through a callable/leaderboard row. This
// module exists so a bad, stale, or attacker-controlled value can never
// become an `Image`/`NetworkImage` request to a host this app does not
// trust — a full structural re-check at the one place every avatar photo
// in the app is rendered from, never a `startsWith`/prefix check.

/// Port the Storage emulator listens on, matching the literal `9199`
/// passed to `FirebaseStorage.instance.useStorageEmulator(...)` in
/// `runiac_firebase_bootstrap.dart`.
const _avatarStorageEmulatorPort = 9199;

final RegExp _avatarObjectPathPattern = RegExp(r'^avatars/[0-9a-f]{32}\.png$');

final RegExp _downloadTokenPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Resolves the live Storage bucket this app is configured against.
///
/// `firebase_storage: ^13.0.5` (resolved 13.4.5 in this workspace) exposes
/// `FirebaseStorage.instance.bucket` as a plain synchronous `String`
/// getter (not a `Future`), so it can be read directly with no async
/// plumbing. Returns `''` — never throws — whenever no Firebase app has
/// been initialised at all, which is the normal state for a widget test
/// that never calls `Firebase.initializeApp()`.
String _defaultAvatarStorageBucket() {
  if (Firebase.apps.isEmpty) {
    return '';
  }
  try {
    return FirebaseStorage.instance.bucket;
  } catch (_) {
    return '';
  }
}

/// Settable seam so a test can supply a fixed bucket name without standing
/// up a real (or emulator-mocked) Firebase app, mirroring
/// [avatarImageProviderFactory] below. Production code never reassigns
/// this; only test files do, and must restore it in `tearDown`.
@visibleForTesting
String Function() avatarStorageBucketResolver = _defaultAvatarStorageBucket;

/// Settable seam so a widget test can inject a synchronous, non-network
/// [ImageProvider] (e.g. a `MemoryImage` or a fake test double) for the
/// photo-renders success case, instead of every avatar-photo test needing
/// a live or faked network image load. Production code never reassigns
/// this; only test files do, and must restore it in `tearDown`.
@visibleForTesting
ImageProvider Function(String url) avatarImageProviderFactory =
    NetworkImage.new;

/// The read-side sanitiser every client render site must call before ever
/// handing a stored `avatarUrl` to [Image]/[NetworkImage]. Mirrors
/// `resolveProfileAvatarUrl` in `functions/src/profile/avatar/avatarPaths.ts`
/// structural check-for-check: `https` (or `http` only when this app is
/// itself pointed at the Storage emulator and the host:port matches it),
/// host exactly `firebasestorage.googleapis.com`, no userinfo, no port, no
/// fragment, path exactly `/v0/b/{bucket}/o/{encoded}`, a percent-decoded
/// object path matching `avatars/{32 lowercase hex}.png`, a query that is
/// exactly `alt=media` plus a UUIDv4-shaped `token`, and an overall length
/// of at most 512 characters. Never throws: garbage, attacker-controlled,
/// or partially-written data all resolve to `''` (treated the same as "no
/// avatar set") instead of raising.
String resolveProfileAvatarUrl(String? rawAvatarUrl) {
  try {
    if (rawAvatarUrl == null) {
      return '';
    }
    final trimmed = rawAvatarUrl.trim();
    if (trimmed.isEmpty || trimmed.length > 512) {
      return '';
    }

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      return '';
    }

    if (uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) {
      return '';
    }

    final bucket = avatarStorageBucketResolver();
    if (bucket.isEmpty) {
      return '';
    }

    if (uri.scheme == 'https') {
      if (uri.host != 'firebasestorage.googleapis.com' || uri.hasPort) {
        return '';
      }
    } else if (uri.scheme == 'http') {
      final config = RuniacFirebaseRuntimeConfig.fromEnvironment();
      if (!config.useFirebaseEmulator) {
        return '';
      }
      final requestHostPort = uri.hasPort
          ? '${uri.host}:${uri.port}'
          : uri.host;
      final allowedHostPort =
          '${config.emulatorHost}:$_avatarStorageEmulatorPort';
      if (requestHostPort != allowedHostPort) {
        return '';
      }
    } else {
      return '';
    }

    final segments = uri.pathSegments;
    if (segments.length != 5 ||
        segments[0] != 'v0' ||
        segments[1] != 'b' ||
        segments[2] != bucket ||
        segments[3] != 'o') {
      return '';
    }
    final decodedObjectPath = segments[4];
    if (!_avatarObjectPathPattern.hasMatch(decodedObjectPath)) {
      return '';
    }

    final rawQuery = uri.query;
    final rawParams = rawQuery.isEmpty
        ? const <String>[]
        : rawQuery.split('&');
    if (rawParams.length != 2) {
      return '';
    }
    final paramNames = rawParams.map((param) => param.split('=').first);
    if (!paramNames.contains('alt') || !paramNames.contains('token')) {
      return '';
    }

    final queryParameters = uri.queryParameters;
    if (queryParameters['alt'] != 'media') {
      return '';
    }
    final token = queryParameters['token'];
    if (token == null || !_downloadTokenPattern.hasMatch(token)) {
      return '';
    }

    return trimmed;
  } catch (_) {
    return '';
  }
}

/// Shared photo-vs-fallback renderer for every avatar surface in the app
/// (the level profile badge disc and the Challenge roster initials
/// avatar). [photoUrl] is treated as untrusted raw input and re-sanitised
/// via [resolveProfileAvatarUrl] here — never passed to [Image] directly —
/// so every call site gets the same defence-in-depth guarantee regardless
/// of what it was given.
///
/// Renders [fallback] whenever there is no sanitised URL, while the first
/// frame has not yet decoded (deliberately no spinner here — see the call
/// sites for why: a spinner would add a second `CustomPaint` next to the
/// level ring and break every ring-finder test), or if the image stream
/// ever errors. The error path is mandatory, not defensive: the server
/// rotates the avatar object path on every replace and deletes the
/// previous-previous generation, so a stale URL will eventually 404
/// wherever it persists (up to an hour in `leaderboardSnapshots`, longer in
/// an in-memory profile cache or old seed data).
class RuniacAvatarPhotoDisc extends StatelessWidget {
  const RuniacAvatarPhotoDisc({
    required this.photoUrl,
    required this.fallback,
    super.key,
  });

  final String? photoUrl;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final sanitizedUrl = resolveProfileAvatarUrl(photoUrl);
    if (sanitizedUrl.isEmpty) {
      return fallback;
    }
    return Padding(
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: Image(
          image: avatarImageProviderFactory(sanitizedUrl),
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (frame == null) {
              return fallback;
            }
            return child;
          },
          errorBuilder: (context, error, stackTrace) => fallback,
        ),
      ),
    );
  }
}
