import 'dart:async';
import 'dart:typed_data';

import 'feed_thumbnail_artifact.dart';

abstract interface class FeedPublishGateway {
  Future<String> stage({
    required String activityId,
    required Uint8List pngBytes,
  });

  Future<FeedPublishResponse> publish({
    required String activityId,
    required String stagingPath,
  });
}

class FeedPublishResponse {
  const FeedPublishResponse({required this.postId});

  final String postId;
}

class FeedPublishException implements Exception {
  const FeedPublishException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Serialises a user-confirmed upload/publish sequence per source activity.
/// No work starts until [publishAfterConfirmation] is explicitly called.
class FeedPublishService {
  FeedPublishService({
    required this.gateway,
    this.operationTimeout = const Duration(seconds: 15),
  });

  final FeedPublishGateway gateway;
  final Duration operationTimeout;
  final Map<String, Future<FeedPublishResponse>> _inFlight =
      <String, Future<FeedPublishResponse>>{};

  Future<FeedPublishResponse> publishAfterConfirmation({
    required String activityId,
    required FeedThumbnailArtifact artifact,
  }) {
    if (activityId.isEmpty) {
      return Future<FeedPublishResponse>.error(
        const FeedPublishException('This run is not ready to post yet.'),
      );
    }
    final existing = _inFlight[activityId];
    if (existing != null) return existing;

    final pending = _stageThenPublish(activityId, artifact);
    _inFlight[activityId] = pending;
    void clearInFlight() {
      if (identical(_inFlight[activityId], pending)) {
        _inFlight.remove(activityId);
      }
    }

    pending.then<void>(
      (_) => clearInFlight(),
      onError: (Object error, StackTrace stackTrace) => clearInFlight(),
    );
    return pending;
  }

  Future<FeedPublishResponse> _stageThenPublish(
    String activityId,
    FeedThumbnailArtifact artifact,
  ) async {
    try {
      final stagingPath = await gateway
          .stage(activityId: activityId, pngBytes: artifact.pngBytes)
          .timeout(operationTimeout);
      return await gateway
          .publish(activityId: activityId, stagingPath: stagingPath)
          .timeout(operationTimeout);
    } on FeedPublishException {
      rethrow;
    } on TimeoutException {
      throw const FeedPublishException(
        'Posting timed out. Check that Firebase Storage and Functions are running, then try again.',
      );
    } on Object catch (error) {
      throw FeedPublishException(_unexpectedPublishMessage(error));
    }
  }
}

String _unexpectedPublishMessage(Object error) {
  final description = _compactErrorDescription(error);
  if (description.isEmpty) {
    return 'Posting failed for an unknown reason. Your run is still saved.';
  }
  return 'Posting failed: $description. Your run is still saved.';
}

String _compactErrorDescription(Object error) {
  final description = error.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (description.isEmpty) return '';
  const maxLength = 140;
  if (description.length <= maxLength) return description;
  return '${description.substring(0, maxLength - 1)}…';
}
