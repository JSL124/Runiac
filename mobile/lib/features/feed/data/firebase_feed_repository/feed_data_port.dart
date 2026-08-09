import 'dart:typed_data';

import '../../domain/models/feed_display_models.dart';

/// Raised only when a single author's query is no longer authorized.
class FeedAuthorPermissionDenied implements Exception {
  const FeedAuthorPermissionDenied(this.authorUid);

  final String authorUid;
}

/// A page of trusted documents with an opaque, stable document-id cursor.
class FeedIdPage {
  const FeedIdPage({
    required this.ids,
    required this.fromCache,
    this.nextDocumentId,
  });

  final List<String> ids;
  final bool fromCache;
  final String? nextDocumentId;
}

/// A minimal post projection. It excludes private profiles and route data.
class FeedPostDocument {
  const FeedPostDocument({
    required this.postId,
    required this.authorUid,
    required this.authorDisplayName,
    required this.authorAvatarInitials,
    required this.authorLevelLabel,
    required this.createdAt,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.averagePaceSecondsPerKm,
    required this.likeCount,
    required this.commentCount,
    required this.viewerLiked,
    required this.viewerCommented,
    this.authorAvatarUrl = '',
  });

  final String postId;
  final String authorUid;
  final String authorDisplayName;
  final String authorAvatarInitials;

  /// Optional stored avatar photo URL, mirroring [authorLevelLabel]'s
  /// optional-and-defensive read. No current backend revision writes this to
  /// `feedPosts` — every value seen in production comes from the live
  /// author-level overlay instead — but the field exists so a post can never
  /// silently lose a future stored value, and so the overlay's
  /// never-erase-a-stored-value contract is meaningful for this field too.
  final String authorAvatarUrl;
  final String authorLevelLabel;
  final DateTime createdAt;
  final int distanceMeters;
  final int durationSeconds;
  final int averagePaceSecondsPerKm;
  final int likeCount;
  final int commentCount;
  final bool viewerLiked;
  final bool viewerCommented;
}

class FeedPostPage {
  const FeedPostPage({
    required this.posts,
    required this.fromCache,
    this.nextCursor,
  });

  final List<FeedPostDocument> posts;
  final bool fromCache;
  final FeedPostCursor? nextCursor;
}

/// Firestore projection for one flat comment. It contains no replies or
/// reaction state, intentionally keeping the social contract narrow.
class FeedCommentDocument {
  const FeedCommentDocument({
    required this.commentId,
    required this.authorUid,
    required this.authorDisplayName,
    required this.authorAvatarInitials,
    required this.authorLevelLabel,
    required this.body,
    required this.createdAt,
  });

  final String commentId;
  final String authorUid;
  final String authorDisplayName;
  final String authorAvatarInitials;
  final String authorLevelLabel;
  final String body;
  final DateTime createdAt;
}

class FeedCommentDocumentPage {
  const FeedCommentDocumentPage({
    required this.comments,
    required this.fromCache,
    this.nextCursor,
  });

  final List<FeedCommentDocument> comments;
  final bool fromCache;
  final FeedCommentCursor? nextCursor;
}

/// A live, backend-owned author snapshot resolved at display time.
///
/// A post or comment stores `authorDisplayName`, `authorAvatarInitials`, and
/// `authorLevelLabel` frozen at write time. All three go stale — a runner who
/// renames themselves would otherwise keep appearing under their old name on
/// every post they already published, and `feedPosts` is closed to client
/// writes so nothing can rewrite the stored copy. This type carries the
/// author's CURRENT identity and level as returned by the backend so the
/// client can overlay them. The client only transports and renders these
/// values; it never computes them.
///
/// An empty [displayName], [avatarInitials], or [levelLabel] means the backend
/// resolved nothing for that field, and the caller must keep its stored value
/// rather than blanking the author out.
class FeedAuthorLevel {
  const FeedAuthorLevel({
    required this.levelLabel,
    required this.levelProgressFraction,
    this.displayName = '',
    this.avatarInitials = '',
    this.avatarUrl = '',
  });

  final String levelLabel;

  /// 0.0..1.0, already converted from the backend's 0..100 percent.
  final double levelProgressFraction;

  /// The author's current name, nickname-first, as the backend resolved it.
  final String displayName;

  /// The author's current avatar initials.
  final String avatarInitials;

  /// The author's current, not-yet-sanitised avatar photo URL. Empty when
  /// the backend resolved no photo for this author.
  final String avatarUrl;
}

/// Typed Firestore/Functions boundary. Tests replace it without Firebase.
abstract interface class FeedDataPort {
  Future<FeedIdPage> pageAcceptedFriends({
    required String viewerUid,
    String? afterDocumentId,
  });

  Future<FeedIdPage> pageHiddenPostIds({
    required String viewerUid,
    String? afterDocumentId,
  });

  Future<FeedPostPage> pagePublishedPosts({
    required String authorUid,
    required String viewerUid,
    FeedPostCursor? after,
  });

  /// Reads one published post directly by id, bypassing the friend-buffered
  /// paging path entirely.
  ///
  /// Exists for feed-engagement notification tap-through: the feed is
  /// ordered by post creation time, so a notified post (a friend liked or
  /// commented on it) can sit arbitrarily deep in the timeline — paging
  /// until it turns up would cost one query per friend per page. A direct
  /// `feedPosts/{postId}` document read is O(1) regardless of how old the
  /// post is, and `firestore.rules` permits it because a feed-engagement
  /// notification is only ever delivered to a post's own owner.
  ///
  /// Returns `null`, never throws, for: the document not existing, its
  /// `status` not being `'published'`, and a permission denial. Any other
  /// failure (offline, a malformed document) may still throw so a caller can
  /// tell "genuinely not there" apart from "could not be resolved right
  /// now".
  Future<FeedPostDocument?> readPublishedPost(String postId);

  Future<FeedCommentDocumentPage> pageComments({
    required String postId,
    FeedCommentCursor? startAfter,
  });

  Future<void> setViewerLike({
    required String viewerUid,
    required String postId,
    required bool isLiked,
  });

  Future<void> createComment({
    required String viewerUid,
    required FeedCommentMutation mutation,
  });

  Future<void> updateComment({
    required String viewerUid,
    required FeedCommentMutation mutation,
  });

  Future<void> deleteComment({
    required String viewerUid,
    required String postId,
    required String commentId,
  });

  Future<void> callPostAction({required String action, required String postId});

  Future<Uint8List> readThumbnail(String postId);

  /// Resolves live author levels for [uids]. A uid the viewer may not see,
  /// or that the backend has no snapshot for, is simply absent from the
  /// result — callers must fall back to their own stored label.
  /// Live identity and level for [uids].
  ///
  /// [postId] names the post whose comments these uids authored, when the
  /// caller is resolving a comment page. It exists because `firestore.rules`
  /// authorizes a comment through its POST, not its commenter: two runners
  /// who share a friend but not each other still read each other's comments
  /// on that friend's post, and without the post as context the backend has
  /// no permitted way to resolve the other commenter. The server proves the
  /// post is readable and that each uid really commented on it; a wrong or
  /// invented [postId] resolves nothing.
  Future<Map<String, FeedAuthorLevel>> fetchAuthorLevels(
    List<String> uids, {
    String? postId,
  });
}
