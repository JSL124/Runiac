import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/feed_display_models.dart';
import '../comments/firebase_feed_comment_page_port.dart';
import 'feed_data_port.dart';
import 'firebase_feed_post_mapper.dart';

class FeedAuthorQueryShape {
  const FeedAuthorQueryShape({
    required this.authorUid,
    required this.status,
    required this.limit,
  });

  final String authorUid;
  final String status;
  final int limit;
}

abstract interface class FeedQueryObserver {
  void onAuthorQuery(FeedAuthorQueryShape shape);
}

/// FlutterFire adapter that makes only per-author Feed reads.
class FirebaseFeedDataPort implements FeedDataPort {
  FirebaseFeedDataPort({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    this.queryObserver,
  }) : _firestoreOverride = firestore,
       _functionsOverride = functions;

  final FirebaseFirestore? _firestoreOverride;
  final FirebaseFunctions? _functionsOverride;
  final FeedQueryObserver? queryObserver;

  FirebaseFirestore get _firestore =>
      _firestoreOverride ?? FirebaseFirestore.instance;
  FirebaseFunctions get _functions =>
      _functionsOverride ??
      FirebaseFunctions.instanceFor(region: 'asia-southeast1');

  @override
  Future<FeedIdPage> pageAcceptedFriends({
    required String viewerUid,
    String? afterDocumentId,
  }) => _pageIds(
    _firestore.collection('users').doc(viewerUid).collection('friends'),
    afterDocumentId,
  );

  @override
  Future<FeedIdPage> pageHiddenPostIds({
    required String viewerUid,
    String? afterDocumentId,
  }) => _pageIds(
    _firestore.collection('users').doc(viewerUid).collection('hiddenFeedPosts'),
    afterDocumentId,
  );

  @override
  Future<FeedPostPage> pagePublishedPosts({
    required String authorUid,
    required String viewerUid,
    FeedPostCursor? after,
  }) => guardAuthorPage(authorUid, () async {
    queryObserver?.onAuthorQuery(
      FeedAuthorQueryShape(
        authorUid: authorUid,
        status: 'published',
        limit: 20,
      ),
    );
    Query<Map<String, Object?>> query = _firestore
        .collection('feedPosts')
        .where('authorUid', isEqualTo: authorUid)
        .where('status', isEqualTo: 'published')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(20);
    if (after != null) {
      query = query.startAfter(<Object>[
        after.createdAt.toUtc().toIso8601String(),
        after.postId,
      ]);
    }
    final snapshot = await query.get();
    final posts = await Future.wait(
      snapshot.docs.map(
        (document) => FirebaseFeedPostMapper.map(document, viewerUid),
      ),
    );
    final last = snapshot.docs.isEmpty ? null : posts.last;
    return FeedPostPage(
      posts: posts,
      fromCache: snapshot.metadata.isFromCache,
      nextCursor: last == null
          ? null
          : FeedPostCursor(createdAt: last.createdAt, postId: last.postId),
    );
  });

  /// Reads one published post by id, server-only.
  ///
  /// `Source.server` is deliberate, not incidental. Firestore's default
  /// `get()` falls back to the local cache when the network is unreachable and
  /// does NOT throw, and unlike `pagePublishedPosts` — which propagates
  /// `snapshot.metadata.isFromCache` into `FeedTimelineSource.cachedOffline`
  /// and thereby turns `mutationsEnabled` off — a single document read has no
  /// provenance channel back to the timeline state. A cached hit here would
  /// therefore resolve a post whose stale snapshot still says
  /// `status == 'published'` and `canComment`, while the timeline's older
  /// server-backed state still reports mutations enabled, and the comment
  /// sheet would open on a post that may already be deleted or unpublished.
  /// Failing loudly instead lets the caller report "unavailable".
  @override
  Future<FeedPostDocument?> readPublishedPost(String postId) async {
    try {
      final document = await _firestore
          .collection('feedPosts')
          .doc(postId)
          .get(const GetOptions(source: Source.server));
      final data = document.data();
      if (!document.exists || data == null || data['status'] != 'published') {
        return null;
      }
      final post = FirebaseFeedPostMapper.fromData(document.id, data);
      // A feed-engagement notification is only ever delivered to a post's
      // owner, so the viewer resolving it here is always that author. Reuse
      // the exact per-viewer like/comment probe `pagePublishedPosts` runs,
      // scoped to the author's own uid — and hold it to the same server-only
      // rule, or the probe could serve stale liked/commented flags from cache
      // even though the post document itself came from the server.
      return await FirebaseFeedPostMapper.mapReference(
        document.reference,
        post,
        post.authorUid,
        source: Source.server,
      );
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') return null;
      // Everything else — notably `unavailable` from the server-only read
      // while offline — propagates, so the controller can distinguish "the
      // post is genuinely gone" from "we could not check" and keep the
      // comment sheet shut in the second case.
      rethrow;
    } on FormatException {
      // A malformed document is indistinguishable from "not there" to the
      // caller, and both resolve to the same not-found outcome.
      return null;
    }
  }

  @override
  Future<FeedCommentDocumentPage> pageComments({
    required String postId,
    FeedCommentCursor? startAfter,
  }) => FirebaseFeedCommentPagePort.load(
    firestore: _firestore,
    postId: postId,
    startAfter: startAfter,
  );

  static Future<T> guardAuthorPage<T>(
    String authorUid,
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw FeedAuthorPermissionDenied(authorUid);
      }
      rethrow;
    }
  }

  @override
  Future<void> setViewerLike({
    required String viewerUid,
    required String postId,
    required bool isLiked,
  }) {
    final reference = _firestore
        .collection('feedPosts')
        .doc(postId)
        .collection('likes')
        .doc(viewerUid);
    return isLiked
        ? reference.set(<String, Object>{
            'userUid': viewerUid,
            'createdAt': FieldValue.serverTimestamp(),
          })
        : reference.delete();
  }

  @override
  Future<void> createComment({
    required String viewerUid,
    required FeedCommentMutation mutation,
  }) async {
    final profile = await _firestore
        .collection('userProfiles')
        .doc(viewerUid)
        .get();
    final profileData = profile.data();
    final displayName = profileData?['displayName'];
    final avatarInitials = profileData?['avatarInitials'];
    final levelLabel = profileData?['levelLabel'];
    if (displayName is! String ||
        displayName.isEmpty ||
        avatarInitials is! String ||
        avatarInitials.isEmpty) {
      throw const FormatException('Comment author profile is invalid.');
    }
    final reference = _firestore
        .collection('feedPosts')
        .doc(mutation.postId)
        .collection('comments')
        .doc();
    await reference.set(<String, Object>{
      'authorUid': viewerUid,
      'authorDisplayName': displayName,
      'authorAvatarInitials': avatarInitials,
      if (levelLabel is String) 'authorLevelLabel': levelLabel,
      'body': mutation.body,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateComment({
    required String viewerUid,
    required FeedCommentMutation mutation,
  }) {
    final commentId = mutation.commentId;
    if (commentId == null) throw ArgumentError.value(commentId, 'commentId');
    return _firestore
        .collection('feedPosts')
        .doc(mutation.postId)
        .collection('comments')
        .doc(commentId)
        .update(<String, Object>{
          'body': mutation.body,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Future<void> deleteComment({
    required String viewerUid,
    required String postId,
    required String commentId,
  }) => _firestore
      .collection('feedPosts')
      .doc(postId)
      .collection('comments')
      .doc(commentId)
      .delete();

  @override
  Future<void> callPostAction({
    required String action,
    required String postId,
  }) {
    return _functions.httpsCallable(action).call(<String, Object>{
      'postId': postId,
    });
  }

  @override
  Future<Uint8List> readThumbnail(String postId) async {
    final result = await _functions.httpsCallable('readFeedThumbnail').call(
      <String, Object>{'postId': postId},
    );
    final raw = result.data;
    if (raw is! Map<Object?, Object?> || raw['base64Png'] is! String) {
      throw const FormatException('Feed thumbnail response is invalid.');
    }
    return Uint8List.fromList(base64Decode(raw['base64Png']! as String));
  }

  static const int _authorLevelChunkSize = 50;

  @override
  Future<Map<String, FeedAuthorLevel>> fetchAuthorLevels(
    List<String> uids, {
    String? postId,
  }) async {
    final distinct = uids.toSet().toList(growable: false);
    if (distinct.isEmpty) return const <String, FeedAuthorLevel>{};
    final callable = _functions.httpsCallable('getFeedAuthorLevels');
    final levels = <String, FeedAuthorLevel>{};
    final scopedPostId = postId?.trim() ?? '';
    for (final chunk in chunkFeedAuthorUids(distinct)) {
      // The uid-only payload stays byte-identical when no post is in scope,
      // so a backend that predates the post-scoped form keeps answering it.
      final result = await callable.call(
        scopedPostId.isEmpty
            ? <String, Object>{'uids': chunk}
            : <String, Object>{'uids': chunk, 'postId': scopedPostId},
      );
      levels.addAll(parseFeedAuthorLevelsResponse(result.data));
    }
    return levels;
  }

  /// Splits [uids] into calls of at most [chunkSize] each. The backend caps
  /// `getFeedAuthorLevels` at 50 uids per invocation.
  @visibleForTesting
  static List<List<String>> chunkFeedAuthorUids(
    List<String> uids, {
    int chunkSize = _authorLevelChunkSize,
  }) {
    final chunks = <List<String>>[];
    for (var start = 0; start < uids.length; start += chunkSize) {
      final end = start + chunkSize < uids.length
          ? start + chunkSize
          : uids.length;
      chunks.add(uids.sublist(start, end));
    }
    return chunks;
  }

  /// Defensively parses a `getFeedAuthorLevels` response into
  /// [FeedAuthorLevel]s, skipping any entry that isn't shaped as documented.
  @visibleForTesting
  static Map<String, FeedAuthorLevel> parseFeedAuthorLevelsResponse(
    Object? raw,
  ) {
    final result = <String, FeedAuthorLevel>{};
    if (raw is! Map<Object?, Object?>) return result;
    final levels = raw['levels'];
    if (levels is! Map<Object?, Object?>) return result;
    for (final entry in levels.entries) {
      final uid = entry.key;
      final value = entry.value;
      if (uid is! String || value is! Map<Object?, Object?>) continue;
      final label = value['levelLabel'];
      final percent = value['levelProgressPercent'];
      // displayName/avatarInitials/avatarUrl arrived with a later backend
      // revision, so an older deployment simply omits them and every caller
      // keeps the identity stored on the post or comment.
      final displayName = value['displayName'];
      final avatarInitials = value['avatarInitials'];
      final avatarUrl = value['avatarUrl'];
      result[uid] = FeedAuthorLevel(
        levelLabel: label is String ? label : '',
        levelProgressFraction: percent is num
            ? (percent / 100).clamp(0.0, 1.0).toDouble()
            : 0.0,
        displayName: displayName is String ? displayName : '',
        avatarInitials: avatarInitials is String ? avatarInitials : '',
        avatarUrl: avatarUrl is String ? avatarUrl : '',
      );
    }
    return result;
  }

  Future<FeedIdPage> _pageIds(
    CollectionReference<Map<String, Object?>> collection,
    String? afterDocumentId,
  ) async {
    Query<Map<String, Object?>> query = collection
        .orderBy(FieldPath.documentId)
        .limit(30);
    if (afterDocumentId != null) {
      query = query.startAfter(<Object>[afterDocumentId]);
    }
    final snapshot = await query.get();
    return FeedIdPage(
      ids: snapshot.docs.map((document) => document.id).toList(growable: false),
      fromCache: snapshot.metadata.isFromCache,
      nextDocumentId: snapshot.docs.length == 30 ? snapshot.docs.last.id : null,
    );
  }
}
