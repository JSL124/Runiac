import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../run/domain/models/run_summary_snapshot.dart';
import '../domain/models/feed_display_models.dart';

class CurrentSessionFeedStore extends ChangeNotifier {
  static const _maximumThumbnailEntries = 20;

  CurrentSessionFeedStore({String? ownerUid}) : this._withOwner(ownerUid);

  CurrentSessionFeedStore._withOwner(this._ownerUid);

  final List<FeedPostReadModel> _sessionPosts = <FeedPostReadModel>[];
  final LinkedHashMap<String, Uint8List> _thumbnailCache =
      LinkedHashMap<String, Uint8List>();
  var _nextPostSequence = 1;
  var _ownerRevision = 0;
  String? _ownerUid;
  FeedAuthorProfileSnapshot? _authorProfile;

  List<FeedPostReadModel> get sessionPosts => List.unmodifiable(_sessionPosts);
  int get ownerRevision => _ownerRevision;
  String? get ownerUid => _ownerUid;
  FeedAuthorProfileSnapshot get authorProfile =>
      _authorProfile ??
      FeedAuthorProfileSnapshot.fallback(userId: _ownerUid ?? '');

  void syncOwner(String? ownerUid) {
    if (_ownerUid == ownerUid) {
      return;
    }
    _ownerUid = ownerUid;
    _authorProfile = null;
    _ownerRevision += 1;
    _sessionPosts.clear();
    _thumbnailCache.clear();
    _nextPostSequence = 1;
    notifyListeners();
  }

  void updateAuthorProfile(FeedAuthorProfileSnapshot profile) {
    if (_authorProfile == profile) {
      return;
    }
    _authorProfile = profile;
    for (var index = 0; index < _sessionPosts.length; index += 1) {
      final post = _sessionPosts[index];
      if (post.authorUserId == profile.userId && _usesFallbackLevel(post)) {
        _sessionPosts[index] = post.copyWith(
          authorDisplayName: profile.displayName,
          authorAvatarInitials: profile.avatarInitials,
          authorAvatarUrl: profile.avatarUrl,
          authorLevelLabel: profile.levelLabel,
        );
      }
    }
    notifyListeners();
  }

  void cachePublishedThumbnail(String postId, Uint8List bytes) {
    if (postId.isEmpty || bytes.lengthInBytes < 8) return;
    _thumbnailCache.remove(postId);
    _thumbnailCache[postId] = bytes;
    while (_thumbnailCache.length > _maximumThumbnailEntries) {
      _thumbnailCache.remove(_thumbnailCache.keys.first);
    }
  }

  Uint8List? thumbnailFor(String postId) {
    final bytes = _thumbnailCache.remove(postId);
    if (bytes != null) _thumbnailCache[postId] = bytes;
    return bytes;
  }

  void shareRunSummary(RunSummarySnapshot summary) {
    final profile = authorProfile;
    _sessionPosts.insert(
      0,
      FeedPostReadModel(
        postId: 'feed-session-${_nextPostSequence++}',
        authorUserId: profile.userId.isEmpty
            ? 'runner-current'
            : profile.userId,
        authorDisplayName: profile.displayName,
        authorAvatarInitials: profile.avatarInitials,
        authorAvatarUrl: profile.avatarUrl,
        authorLevelLabel: profile.levelLabel,
        relativeTimeLabel: summary.dateTimeLabel,
        activityTitle: summary.title,
        routeName: summary.routeName,
        distanceLabel: '${summary.distanceKm} km',
        paceLabel: '${summary.avgPace} / km',
        durationLabel: summary.duration,
        likeCount: 0,
        commentCount: 0,
        isLikedByViewer: false,
        hasViewerCommented: false,
        canComment: true,
        showsOwnerMenu: true,
        routeThumbnail: const FeedRouteThumbnailReadModel(
          thumbnailKey: 'session-shared-route',
          accessibilityLabel: 'A simplified shared route preview',
        ),
      ),
    );
    notifyListeners();
  }

  bool toggleLike(String postId) {
    final index = _sessionPosts.indexWhere((post) => post.postId == postId);
    if (index == -1) {
      return false;
    }
    final post = _sessionPosts[index];
    final isLiked = !post.isLikedByViewer;
    _sessionPosts[index] = post.copyWith(
      isLikedByViewer: isLiked,
      likeCount: post.likeCount + (isLiked ? 1 : -1),
    );
    notifyListeners();
    return true;
  }

  bool addComment(String postId) {
    final index = _sessionPosts.indexWhere((post) => post.postId == postId);
    if (index == -1) {
      return false;
    }
    final post = _sessionPosts[index];
    _sessionPosts[index] = post.copyWith(
      commentCount: post.commentCount + 1,
      hasViewerCommented: true,
    );
    notifyListeners();
    return true;
  }

  bool removePost(String postId) {
    final beforeCount = _sessionPosts.length;
    _sessionPosts.removeWhere((post) => post.postId == postId);
    if (_sessionPosts.length == beforeCount) {
      return false;
    }
    notifyListeners();
    return true;
  }
}

bool _usesFallbackLevel(FeedPostReadModel post) {
  final label = post.authorLevelLabel.trim();
  return label.isEmpty || label == 'Level 0' || label == 'Lv.0';
}

class CurrentSessionFeedScope
    extends InheritedNotifier<CurrentSessionFeedStore> {
  const CurrentSessionFeedScope({
    required CurrentSessionFeedStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static CurrentSessionFeedStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CurrentSessionFeedScope>()
        ?.notifier;
  }

  static CurrentSessionFeedStore? maybeRead(BuildContext context) {
    return context
        .getInheritedWidgetOfExactType<CurrentSessionFeedScope>()
        ?.notifier;
  }
}
