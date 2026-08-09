import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Machine-readable failure reason carried on [AvatarUploadException],
/// mirroring `AVATAR_REPLACE_COOLDOWN_REASON` in
/// `functions/src/profile/avatar/core.ts`. [unknown] covers every other
/// failure path (network, staged-object validation, a generic
/// `FirebaseException`) so the UI can always render *some* English message
/// without string-matching server text, the same way
/// `firestore_user_profile_persistence_repository.dart` special-cases
/// `NICKNAME_UNAVAILABLE` by machine-readable reason rather than message text.
enum AvatarUploadFailureReason { cooldown, unknown }

/// Thrown by [AvatarUploadGateway] with an already-English, user-facing
/// [message]. Callers never need to interpret a raw [FirebaseException] or
/// [FirebaseFunctionsException] themselves.
class AvatarUploadException implements Exception {
  const AvatarUploadException(this.reason, this.message);

  final AvatarUploadFailureReason reason;
  final String message;

  @override
  String toString() => 'AvatarUploadException($reason, $message)';
}

/// Upload/removal seam for the Edit Profile avatar flow. Kept as its own
/// interface (rather than a bare function) so widget tests can hand-write an
/// `implements` stub that records call counts and simulates every failure
/// reason — this repo has no mocking framework.
abstract interface class AvatarUploadGateway {
  /// Stages [pngBytes] in Storage, then promotes it via the `setProfileAvatar`
  /// callable. Returns the new, already-sanitised-server-side `avatarUrl`.
  Future<String> upload(Uint8List pngBytes);

  /// Clears the caller's avatar via the `clearProfileAvatar` callable.
  Future<void> clear();
}

/// Production [AvatarUploadGateway]. The constructor DI seam (optional
/// [FirebaseAuth]/[FirebaseStorage]/[FirebaseFunctions]/[Random], each
/// defaulting to the live singleton) mirrors `FirebaseFeedPublishGateway` in
/// `../../../feed/data/feed_publish/firebase_feed_publish_gateway.dart` so
/// this gateway can be constructed with fakes in tests without any
/// mocking framework.
class FirebaseAvatarUploadGateway implements AvatarUploadGateway {
  FirebaseAvatarUploadGateway({
    FirebaseAuth? auth,
    FirebaseStorage? storage,
    FirebaseFunctions? functions,
    Random? random,
  }) : _auth = auth ?? FirebaseAuth.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _functions =
           functions ??
           FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
       _random = random ?? Random.secure();

  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  final FirebaseFunctions _functions;
  final Random _random;

  @override
  Future<String> upload(Uint8List pngBytes) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw const AvatarUploadException(
        AvatarUploadFailureReason.unknown,
        'Sign in again before changing your profile photo.',
      );
    }
    if (pngBytes.isEmpty || pngBytes.lengthInBytes > _maxPngBytes) {
      throw const AvatarUploadException(
        AvatarUploadFailureReason.unknown,
        'This photo could not be processed. Try a different photo.',
      );
    }

    final path = 'avatar-staging/$uid/${_newUploadId()}.png';
    try {
      await _storage
          .ref(path)
          .putData(
            pngBytes,
            SettableMetadata(
              contentType: 'image/png',
              customMetadata: <String, String>{'ownerUid': uid},
            ),
          );
    } on FirebaseException catch (error) {
      throw AvatarUploadException(
        AvatarUploadFailureReason.unknown,
        _firebaseMessage(error, fallback: 'Photo upload failed. Try again.'),
      );
    }

    final HttpsCallableResult<Object?> response;
    try {
      response = await _functions.httpsCallable('setProfileAvatar').call(
        <String, Object?>{'stagingPath': path},
      );
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionsException(
        error,
        fallback: 'We could not update your profile photo. Try again.',
      );
    }

    final data = response.data;
    final avatarUrl = data is Map<Object?, Object?> ? data['avatarUrl'] : null;
    if (avatarUrl is! String || avatarUrl.isEmpty) {
      throw const AvatarUploadException(
        AvatarUploadFailureReason.unknown,
        'We could not update your profile photo. Try again.',
      );
    }
    return avatarUrl;
  }

  @override
  Future<void> clear() async {
    try {
      await _functions.httpsCallable('clearProfileAvatar').call();
    } on FirebaseFunctionsException catch (error) {
      throw _mapFunctionsException(
        error,
        fallback: 'We could not remove your profile photo. Try again.',
      );
    }
  }

  String _newUploadId() {
    final values = List<int>.generate(16, (_) => _random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  AvatarUploadException _mapFunctionsException(
    FirebaseFunctionsException error, {
    required String fallback,
  }) {
    final reason = error.details is Map<Object?, Object?>
        ? (error.details as Map<Object?, Object?>)['reason']
        : null;
    if (reason == 'avatar_replace_cooldown') {
      return const AvatarUploadException(
        AvatarUploadFailureReason.cooldown,
        'You can only change your profile photo once a minute. Try again shortly.',
      );
    }
    return AvatarUploadException(
      AvatarUploadFailureReason.unknown,
      _functionsMessage(error, fallback: fallback),
    );
  }
}

String _firebaseMessage(FirebaseException error, {required String fallback}) {
  final message = error.message?.trim();
  if (message == null || message.isEmpty) return fallback;
  return message;
}

String _functionsMessage(
  FirebaseFunctionsException error, {
  required String fallback,
}) {
  final message = error.message?.trim();
  if (message == null || message.isEmpty) return fallback;
  return message;
}

const _maxPngBytes = 1024 * 1024;
