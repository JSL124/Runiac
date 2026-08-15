import 'package:cloud_firestore/cloud_firestore.dart';

import 'feed_data_port.dart';

class FirebaseFeedPostMapper {
  const FirebaseFeedPostMapper._();

  /// `async` is load-bearing, not decoration. Without it, the `fromData` call
  /// below runs while the caller is still *building* the iterable it hands to
  /// `Future.wait`, so a malformed document throws synchronously out of
  /// `snapshot.docs.map(...)` and aborts the whole batch before a single probe
  /// is issued. As an `async` body the same failure arrives as a rejected
  /// future, which `Future.wait` collects like any other.
  static Future<FeedPostDocument> map(
    QueryDocumentSnapshot<Map<String, Object?>> document,
    String viewerUid,
  ) async => mapReference(
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
    // Deliberately `Future.wait`, never a record `(a, b).wait`. The record
    // form reports any failure as `ParallelWaitError`, which is not a
    // `FirebaseException` — so `FirebaseFeedDataPort.guardAuthorPage` could
    // never recognise a `permission-denied` probe, and one denied like or
    // comment read escaped every per-author guard and failed the entire
    // timeline instead of the single author it belongs to. `Future.wait`
    // rethrows the first underlying error unchanged, still runs both reads
    // concurrently, and still awaits both, so the loser of a race can never
    // become an unhandled async error.
    // The comments probe below is COLLECTION-scoped (one post's subcollection),
    // not a collection-group query, and it needs a matching single-field index
    // on `comments.authorUid`. Firestore indexes that automatically — but a
    // `fieldOverrides` entry for a field REPLACES the automatic indexing, so
    // declaring only COLLECTION_GROUP there (which the account-deletion sweep
    // needs) silently deletes the COLLECTION-scope indexes this query runs on
    // and the whole timeline fails `failed-precondition`. Both scopes are
    // therefore declared together in `firestore.indexes.json`; removing either
    // breaks one of the two readers.
    final probes = await Future.wait<Object?>(<Future<Object?>>[
      reference.collection('likes').doc(viewerUid).get(options),
      reference
          .collection('comments')
          .where('authorUid', isEqualTo: viewerUid)
          .limit(1)
          .get(options),
    ]);
    final liked = probes[0]! as DocumentSnapshot<Map<String, Object?>>;
    final comments = probes[1]! as QuerySnapshot<Map<String, Object?>>;
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
