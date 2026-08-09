import 'dart:typed_data';

/// Read-only viewer context used to scope a Feed read.
class FeedViewerContext {
  const FeedViewerContext({
    required this.currentUserId,
    required this.acceptedFriendUserIds,
  });

  final String currentUserId;
  final Set<String> acceptedFriendUserIds;
}

/// Read-only collection returned by a Feed repository.
class FeedReadModel {
  FeedReadModel({required List<FeedPostReadModel> posts})
    : posts = List.unmodifiable(posts);

  final List<FeedPostReadModel> posts;
}

/// Display-only profile snapshot used by Feed surfaces for the current runner.
///
/// The values are read from the app's existing profile/progress read models.
/// Feed widgets may use this only as a display fallback for the current
/// viewer's own older posts/comments that predate the backend author-level
/// snapshot. It is not a trusted progression source.
class FeedAuthorProfileSnapshot {
  const FeedAuthorProfileSnapshot({
    required this.userId,
    required this.displayName,
    required this.avatarInitials,
    required this.levelLabel,
    required this.levelProgressFraction,
    this.avatarUrl = '',
  });

  final String userId;
  final String displayName;
  final String avatarInitials;

  /// Raw, not-yet-sanitised avatar photo URL. Empty when no photo is set.
  final String avatarUrl;
  final String levelLabel;
  final double levelProgressFraction;

  static FeedAuthorProfileSnapshot fallback({String userId = ''}) =>
      FeedAuthorProfileSnapshot(
        userId: userId,
        displayName: 'You',
        avatarInitials: 'R',
        levelLabel: 'Level 0',
        levelProgressFraction: 0,
      );

  String get compactLevelLabel => compactFeedAuthorLevelLabel(levelLabel);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedAuthorProfileSnapshot &&
          other.userId == userId &&
          other.displayName == displayName &&
          other.avatarInitials == avatarInitials &&
          other.avatarUrl == avatarUrl &&
          other.levelLabel == levelLabel &&
          other.levelProgressFraction == levelProgressFraction;

  @override
  int get hashCode => Object.hash(
    userId,
    displayName,
    avatarInitials,
    avatarUrl,
    levelLabel,
    levelProgressFraction,
  );
}

/// The source of the currently displayed Feed snapshot.
enum FeedTimelineSource { server, cachedOffline }

/// Typed state for a stable, paginated Feed timeline.
///
/// [posts] only contains display-safe post snapshots. It deliberately has no
/// profile, route geometry, entitlement, or competitive data.
class FeedTimelineState extends FeedReadModel {
  FeedTimelineState({
    required super.posts,
    required this.source,
    required this.refreshing,
    required this.exhausted,
    this.recoverableError,
  });

  final FeedTimelineSource source;
  final bool refreshing;
  final bool exhausted;
  final FeedRecoverableError? recoverableError;

  bool get mutationsEnabled => source == FeedTimelineSource.server;
}

/// Non-sensitive error payload suitable for an inline retry affordance.
class FeedRecoverableError {
  const FeedRecoverableError({required this.code, required this.message});

  final String code;
  final String message;
}

/// Display-only Feed post details loaded into a local Feed session.
class FeedPostReadModel {
  const FeedPostReadModel({
    required this.postId,
    required this.authorUserId,
    required this.authorDisplayName,
    required this.authorAvatarInitials,
    required this.authorLevelLabel,
    required this.relativeTimeLabel,
    required this.distanceLabel,
    required this.paceLabel,
    required this.durationLabel,
    required this.likeCount,
    required this.commentCount,
    required this.isLikedByViewer,
    required this.hasViewerCommented,
    required this.canComment,
    required this.showsOwnerMenu,
    required this.routeThumbnail,
    this.authorLevelProgressFraction,
    this.authorAvatarUrl = '',
    this.activityTitle,
    this.routeName,
  });

  final String postId;
  final String authorUserId;
  final String authorDisplayName;
  final String authorAvatarInitials;

  /// Raw, not-yet-sanitised avatar photo URL. `feedPosts` never stores this
  /// at write time (only `authorAvatarInitials` is frozen there), so this is
  /// always populated by the live author-level overlay, never by a stored
  /// document field.
  final String authorAvatarUrl;
  final String authorLevelLabel;

  /// A live, backend-owned 0.0..1.0 progress fraction resolved at display
  /// time. `null` means the author-level overlay resolved nothing for this
  /// post (including "not deployed yet"), which is semantically distinct
  /// from a genuine resolved `0.0` (a runner who just levelled up). See
  /// [authorProfileFor] for how the `null` case is handled.
  final double? authorLevelProgressFraction;
  final String relativeTimeLabel;
  final String distanceLabel;
  final String paceLabel;
  final String durationLabel;
  final int likeCount;
  final int commentCount;
  final bool isLikedByViewer;
  final bool hasViewerCommented;
  final bool canComment;
  final bool showsOwnerMenu;
  final FeedRouteThumbnailReadModel routeThumbnail;
  final String? activityTitle;
  final String? routeName;

  String get likeCountLabel =>
      '$likeCount ${likeCount == 1 ? 'like' : 'likes'}';

  String get compactAuthorLevelLabel =>
      compactFeedAuthorLevelLabel(authorLevelLabel);

  /// Builds the profile snapshot Feed surfaces render.
  ///
  /// [authorLevelLabel] and [authorLevelProgressFraction] already reflect a
  /// resolved live author level when one was available at load time (see
  /// the Feed data layer's author-level overlay); otherwise they hold the
  /// post's stored, potentially stale values. The label priority is:
  /// resolved/stored label on this post first, then — only when this
  /// post's own label is empty — the current viewer's own profile as a
  /// last-resort fallback, so the viewer's own badge never regresses to an
  /// empty label.
  ///
  /// The progress fraction is resolved independently of the label: a `null`
  /// [authorLevelProgressFraction] means the overlay resolved nothing (the
  /// normal state while the resolving callable isn't deployed), so the
  /// current viewer's own live fraction is used for their own post instead
  /// of regressing to an empty ring; a genuine resolved `0.0` is honoured
  /// as-is and is never replaced.
  FeedAuthorProfileSnapshot authorProfileFor(
    FeedAuthorProfileSnapshot? currentViewer,
  ) {
    final isCurrentViewer = currentViewer?.userId == authorUserId;
    final hasOwnLabel = authorLevelLabel.trim().isNotEmpty;
    return FeedAuthorProfileSnapshot(
      userId: authorUserId,
      displayName: authorDisplayName,
      avatarInitials: authorAvatarInitials,
      avatarUrl: authorAvatarUrl,
      levelLabel: hasOwnLabel || !isCurrentViewer
          ? authorLevelLabel
          : currentViewer!.levelLabel,
      levelProgressFraction:
          authorLevelProgressFraction ??
          (isCurrentViewer ? currentViewer!.levelProgressFraction : 0),
    );
  }

  String get commentCountLabel {
    if (commentCount == 0) {
      return 'No comments';
    }
    return '$commentCount ${commentCount == 1 ? 'comment' : 'comments'}';
  }

  FeedPostReadModel copyWith({
    String? authorDisplayName,
    String? authorAvatarInitials,
    String? authorAvatarUrl,
    String? authorLevelLabel,
    double? authorLevelProgressFraction,
    int? likeCount,
    int? commentCount,
    bool? isLikedByViewer,
    bool? hasViewerCommented,
    FeedRouteThumbnailReadModel? routeThumbnail,
  }) {
    return FeedPostReadModel(
      postId: postId,
      authorUserId: authorUserId,
      authorDisplayName: authorDisplayName ?? this.authorDisplayName,
      authorAvatarInitials: authorAvatarInitials ?? this.authorAvatarInitials,
      authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
      authorLevelLabel: authorLevelLabel ?? this.authorLevelLabel,
      authorLevelProgressFraction:
          authorLevelProgressFraction ?? this.authorLevelProgressFraction,
      relativeTimeLabel: relativeTimeLabel,
      distanceLabel: distanceLabel,
      paceLabel: paceLabel,
      durationLabel: durationLabel,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      isLikedByViewer: isLikedByViewer ?? this.isLikedByViewer,
      hasViewerCommented: hasViewerCommented ?? this.hasViewerCommented,
      canComment: canComment,
      showsOwnerMenu: showsOwnerMenu,
      routeThumbnail: routeThumbnail ?? this.routeThumbnail,
      activityTitle: activityTitle,
      routeName: routeName,
    );
  }
}

/// Cursor used only for deterministic Feed post ordering.
class FeedPostCursor {
  const FeedPostCursor({required this.createdAt, required this.postId});

  final DateTime createdAt;
  final String postId;
}

/// Client-owned comment fields; aggregate counts remain server-owned.
class FeedCommentMutation {
  const FeedCommentMutation({
    required this.postId,
    required this.commentId,
    required this.body,
  });

  final String postId;
  final String? commentId;
  final String body;
}

/// A display-safe, flat Feed comment returned by a trusted comment query.
class FeedCommentReadModel {
  const FeedCommentReadModel({
    required this.commentId,
    required this.authorUserId,
    required this.authorDisplayName,
    required this.authorAvatarInitials,
    required this.authorLevelLabel,
    required this.body,
    required this.createdAt,
    this.authorLevelProgressFraction,
    this.authorAvatarUrl = '',
  });

  final String commentId;
  final String authorUserId;
  final String authorDisplayName;
  final String authorAvatarInitials;

  /// Raw, not-yet-sanitised avatar photo URL. Comments never store this at
  /// write time (`firestore.rules` only allows `authorAvatarInitials` on a
  /// comment doc), so this is always populated by the live author-level
  /// overlay, never by a stored document field.
  final String authorAvatarUrl;
  final String authorLevelLabel;

  /// A live, backend-owned 0.0..1.0 progress fraction resolved at display
  /// time. `null` means the author-level overlay resolved nothing for this
  /// comment (including "not deployed yet"), which is semantically distinct
  /// from a genuine resolved `0.0` (a runner who just levelled up). See
  /// [authorProfileFor] for how the `null` case is handled.
  final double? authorLevelProgressFraction;
  final String body;
  final DateTime createdAt;

  String get compactAuthorLevelLabel =>
      compactFeedAuthorLevelLabel(authorLevelLabel);

  /// See [FeedPostReadModel.authorProfileFor] for the fallback priority:
  /// this comment's own (resolved-or-stored) label first, then the current
  /// viewer's own profile only as a last resort for the viewer's own empty
  /// label; the progress fraction is resolved independently — a `null`
  /// value falls back to the current viewer's own live fraction only for
  /// their own comment, while a genuine resolved `0.0` is honoured as-is.
  FeedAuthorProfileSnapshot authorProfileFor(
    FeedAuthorProfileSnapshot? currentViewer,
  ) {
    final isCurrentViewer = currentViewer?.userId == authorUserId;
    final hasOwnLabel = authorLevelLabel.trim().isNotEmpty;
    return FeedAuthorProfileSnapshot(
      userId: authorUserId,
      displayName: authorDisplayName,
      avatarInitials: authorAvatarInitials,
      avatarUrl: authorAvatarUrl,
      levelLabel: hasOwnLabel || !isCurrentViewer
          ? authorLevelLabel
          : currentViewer!.levelLabel,
      levelProgressFraction:
          authorLevelProgressFraction ??
          (isCurrentViewer ? currentViewer!.levelProgressFraction : 0),
    );
  }

  FeedCommentReadModel copyWith({
    String? body,
    String? authorLevelLabel,
    double? authorLevelProgressFraction,
    String? authorAvatarUrl,
  }) => FeedCommentReadModel(
    commentId: commentId,
    authorUserId: authorUserId,
    authorDisplayName: authorDisplayName,
    authorAvatarInitials: authorAvatarInitials,
    authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
    authorLevelLabel: authorLevelLabel ?? this.authorLevelLabel,
    authorLevelProgressFraction:
        authorLevelProgressFraction ?? this.authorLevelProgressFraction,
    body: body ?? this.body,
    createdAt: createdAt,
  );
}

String compactFeedAuthorLevelLabel(String levelLabel) {
  final trimmed = levelLabel.trim();
  if (trimmed.isEmpty) return '';
  final match = RegExp(
    r'^Level\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  return match == null ? trimmed : 'Lv.${match.group(1)!.trim()}';
}

/// Stable newest-first comment cursor: `(createdAt, commentId)` descending.
class FeedCommentCursor {
  const FeedCommentCursor({required this.createdAt, required this.commentId});

  final DateTime createdAt;
  final String commentId;
}

/// One bounded comment page. Counts remain authoritative on the post stream.
class FeedCommentPage {
  FeedCommentPage({
    required List<FeedCommentReadModel> comments,
    required this.source,
    required this.exhausted,
  }) : comments = List.unmodifiable(comments);

  final List<FeedCommentReadModel> comments;
  final FeedTimelineSource source;
  final bool exhausted;

  bool get mutationsEnabled => source == FeedTimelineSource.server;
}

/// Privacy-safe route preview data for a Feed post.
///
/// This model identifies a pre-rendered preview only. It intentionally keeps
/// route geometry and precise location data outside the client display model.
class FeedRouteThumbnailReadModel {
  const FeedRouteThumbnailReadModel({
    required this.thumbnailKey,
    required this.accessibilityLabel,
    this.pngBytes,
  });

  final String thumbnailKey;
  final String accessibilityLabel;
  final Uint8List? pngBytes;

  FeedRouteThumbnailReadModel copyWith({Uint8List? pngBytes}) =>
      FeedRouteThumbnailReadModel(
        thumbnailKey: thumbnailKey,
        accessibilityLabel: accessibilityLabel,
        pngBytes: pngBytes ?? this.pngBytes,
      );
}
