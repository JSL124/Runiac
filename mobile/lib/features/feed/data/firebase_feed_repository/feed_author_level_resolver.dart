import '../../domain/models/feed_display_models.dart';
import 'feed_data_port.dart';

/// Session-scoped cache that overlays live author levels onto Feed posts and
/// comments.
///
/// Each post and comment stores an `authorLevelLabel` frozen at publish
/// time, which can go stale or be entirely absent on older content. This
/// resolver asks [FeedDataPort.fetchAuthorLevels] for the author's CURRENT
/// level and caches it for the life of one Feed session. It never computes
/// a level itself — it only transports whatever the backend already
/// returned.
///
/// Any failure (offline, permission denial, a callable that isn't deployed
/// yet) is swallowed entirely: nothing is cached for that attempt, and every
/// caller keeps using the stored, possibly-stale label. The Feed must always
/// be able to paint even if this resolver never resolves anything.
class FeedAuthorLevelResolver {
  FeedAuthorLevelResolver(this._port);

  final FeedDataPort _port;
  final Map<String, FeedAuthorLevel> _cache = <String, FeedAuthorLevel>{};

  /// The cached live level for [uid], or `null` if none has been resolved.
  FeedAuthorLevel? lookup(String uid) => _cache[uid];

  FeedAuthorLevel? operator [](String uid) => lookup(uid);

  /// Fetches and caches live levels for every uid in [uids] not already
  /// cached. Swallows every error from the port so callers can always fall
  /// back to a post or comment's stored `authorLevelLabel`.
  ///
  /// [postId] is the post whose comments these uids authored, passed straight
  /// through to the backend so it can authorize a commenter the viewer is not
  /// friends with but whose comment they can already read. Omitted for the
  /// timeline, where every author is a post author and the friendship check
  /// already covers them.
  Future<void> ensureResolved(Iterable<String> uids, {String? postId}) async {
    final missing = <String>{
      for (final uid in uids)
        if (!_cache.containsKey(uid)) uid,
    };
    if (missing.isEmpty) return;
    try {
      final resolved = await _port.fetchAuthorLevels(
        missing.toList(growable: false),
        postId: postId,
      );
      _cache.addAll(resolved);
    } catch (_) {
      // Offline, permission-denied, or a not-yet-deployed callable: leave
      // the cache untouched so every caller falls back to the stored label.
    }
  }

  /// Clears every cached level. Called on pull-to-refresh so a fresh Feed
  /// load re-resolves rather than reusing a stale session cache.
  void invalidate() => _cache.clear();

  /// Overlays this resolver's cached live level onto [post]'s author, the
  /// same never-erase-a-stored-value way the timeline paging path overlays
  /// every post it emits.
  ///
  /// Each field is overlaid independently and only when the backend
  /// resolved a non-empty value; [post] is returned unchanged when nothing
  /// is cached for its author, including when [ensureResolved] itself
  /// swallowed a failure. An empty resolved value must never erase what
  /// [post] already carries.
  FeedPostReadModel overlay(FeedPostReadModel post) {
    final resolved = lookup(post.authorUserId);
    if (resolved == null) return post;
    final levelLabel = resolved.levelLabel.trim();
    final displayName = resolved.displayName.trim();
    final avatarInitials = resolved.avatarInitials.trim();
    final avatarUrl = resolved.avatarUrl.trim();
    if (levelLabel.isEmpty &&
        displayName.isEmpty &&
        avatarInitials.isEmpty &&
        avatarUrl.isEmpty) {
      return post;
    }
    return post.copyWith(
      authorDisplayName: displayName.isEmpty ? null : displayName,
      authorAvatarInitials: avatarInitials.isEmpty ? null : avatarInitials,
      authorAvatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
      authorLevelLabel: levelLabel.isEmpty ? null : levelLabel,
      authorLevelProgressFraction: levelLabel.isEmpty
          ? null
          : resolved.levelProgressFraction,
    );
  }
}
