import 'package:cloud_firestore/cloud_firestore.dart';

import 'feed_data_port.dart';

class FirebaseFeedPostMapper {
  const FirebaseFeedPostMapper._();

  static Future<FeedPostDocument> map(
    QueryDocumentSnapshot<Map<String, Object?>> document,
    String viewerUid,
  ) => mapReference(
    document.reference,
    fromData(document.id, document.data()),
    viewerUid,
  );

  /// Runs the same per-viewer like/comment probe as [map], against an
  /// already-decoded [post] and its own [reference].
  ///
  /// [map] can only be called from a `QueryDocumentSnapshot`, which paging
  /// always has. A direct single-document read (a notified post resolved by
  /// id, outside any query) only has a plain `DocumentReference`, so this is
  /// factored out for both to share — the per-viewer probe must stay
  /// identical however the post document was obtained.
  ///
  /// [source] defaults to Firestore's own default, which serves the local
  /// cache when the network is unreachable. Paging depends on that: an
  /// offline timeline is read from cache and marked `cachedOffline`, which is
  /// what disables mutations for it. A caller that has no such provenance
  /// channel — the direct read below — passes [Source.server] so an offline
  /// probe fails loudly instead of silently returning stale liked/commented
  /// flags.
  static Future<FeedPostDocument> mapReference(
    DocumentReference<Map<String, Object?>> reference,
    FeedPostDocument post,
    String viewerUid, {
    Source source = Source.serverAndCache,
  }) async {
    final options = GetOptions(source: source);
    final (liked, comments) = await (
      reference.collection('likes').doc(viewerUid).get(options),
      reference
          .collection('comments')
          .where('authorUid', isEqualTo: viewerUid)
          .limit(1)
          .get(options),
    ).wait;
    return FeedPostDocument(
      postId: post.postId,
      authorUid: post.authorUid,
      authorDisplayName: post.authorDisplayName,
      authorAvatarInitials: post.authorAvatarInitials,
      authorAvatarUrl: post.authorAvatarUrl,
      authorLevelLabel: post.authorLevelLabel,
      createdAt: post.createdAt,
      distanceMeters: post.distanceMeters,
      durationSeconds: post.durationSeconds,
      averagePaceSecondsPerKm: post.averagePaceSecondsPerKm,
      likeCount: post.likeCount,
      commentCount: post.commentCount,
      viewerLiked: liked.exists,
      viewerCommented: comments.docs.isNotEmpty,
    );
  }

  static FeedPostDocument fromData(String id, Map<String, Object?> data) =>
      FeedPostDocument(
        postId: id,
        authorUid: _string(data, 'authorUid'),
        authorDisplayName: _string(data, 'authorDisplayName'),
        authorAvatarInitials: _string(data, 'authorAvatarInitials'),
        authorAvatarUrl: _optionalString(data, 'authorAvatarUrl'),
        authorLevelLabel: _optionalString(data, 'authorLevelLabel'),
        createdAt: _dateTime(data, 'createdAt'),
        distanceMeters: _int(data, 'distanceMeters'),
        durationSeconds: _int(data, 'durationSeconds'),
        averagePaceSecondsPerKm: _int(data, 'averagePaceSecondsPerKm'),
        likeCount: _int(data, 'likeCount'),
        commentCount: _int(data, 'commentCount'),
        viewerLiked: false,
        viewerCommented: false,
      );

  static String _string(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is String && value.isNotEmpty) return value;
    throw FormatException('Feed post field $key is invalid.');
  }

  static String _optionalString(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value == null) return '';
    if (value is String) return value;
    throw FormatException('Feed post field $key is invalid.');
  }

  static int _int(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is int && value >= 0) return value;
    throw FormatException('Feed post field $key is invalid.');
  }

  static DateTime _dateTime(Map<String, Object?> data, String key) {
    final value = data[key];
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    throw FormatException('Feed post field $key is invalid.');
  }
}
