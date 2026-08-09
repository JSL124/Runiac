import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'feed_publish_service.dart';

class FirebaseFeedPublishGateway implements FeedPublishGateway {
  FirebaseFeedPublishGateway({
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
  Future<String> stage({
    required String activityId,
    required Uint8List pngBytes,
  }) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw const FeedPublishException('Sign in before posting this run.');
    }
    if (!_isSafeId(activityId)) {
      throw const FeedPublishException('This run is not ready to post yet.');
    }
    if (pngBytes.isEmpty || pngBytes.lengthInBytes > _maxPngBytes) {
      throw const FeedPublishException(
        'This route preview cannot be posted. Please try again.',
      );
    }

    final upload = FeedStagingUpload.create(
      ownerUid: uid,
      activityId: activityId,
      bytes: pngBytes,
      token: _newUploadId(),
    );
    try {
      await _storage
          .ref(upload.path)
          .putData(
            upload.bytes,
            SettableMetadata(
              contentType: 'image/png',
              customMetadata: upload.metadata,
            ),
          );
    } on FirebaseException catch (error) {
      throw FeedPublishException(
        _firebaseMessage(
          error,
          fallback: 'Route preview upload failed. Your run is still saved.',
        ),
      );
    }
    return upload.path;
  }

  @override
  Future<FeedPublishResponse> publish({
    required String activityId,
    required String stagingPath,
  }) async {
    final callable = _functions.httpsCallable('publishActivityToFeed');
    final HttpsCallableResult<Object?> response;
    try {
      response = await callable.call(<String, Object>{
        'activityId': activityId,
        'stagingPath': stagingPath,
      });
    } on FirebaseFunctionsException catch (error) {
      throw FeedPublishException(
        _functionsMessage(
          error,
          fallback: 'Feed posting was rejected. Your run is still saved.',
        ),
      );
    }
    final data = response.data;
    if (data is! Map<Object?, Object?>) {
      throw const FeedPublishException('Posting did not return a Feed post.');
    }
    final postId = data['postId'];
    if (postId is! String || postId.isEmpty) {
      throw const FeedPublishException('Posting did not return a Feed post.');
    }
    return FeedPublishResponse(postId: postId);
  }

  String _newUploadId() {
    final values = List<int>.generate(16, (_) => _random.nextInt(256));
    return values
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
  }
}

class FeedStagingUpload {
  const FeedStagingUpload._({
    required this.path,
    required this.metadata,
    required this.bytes,
  });
  factory FeedStagingUpload.create({
    required String ownerUid,
    required String activityId,
    required Uint8List bytes,
    required String token,
  }) {
    final uploadName = '$token.png';
    return FeedStagingUpload._(
      path: 'feed-thumbnail-staging/$ownerUid/$activityId/$uploadName',
      metadata: <String, String>{
        'ownerUid': ownerUid,
        'activityId': activityId,
        'uploadId': uploadName,
      },
      bytes: bytes,
    );
  }
  final String path;
  final Map<String, String> metadata;
  final Uint8List bytes;
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

bool _isSafeId(String value) =>
    RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);

const _maxPngBytes = 1024 * 1024;
