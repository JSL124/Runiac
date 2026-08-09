import 'package:flutter/foundation.dart';

import '../domain/models/friends_read_model.dart';

/// A live, backend-owned level snapshot for one friend/request/blocked uid,
/// resolved at display time via `getFriendLevels`.
///
/// The Firestore friend/request/blocked edge documents carry no level data
/// at all, so this is the only source of a Friends-row level. The client
/// only transports and formats these values; it never computes them.
class FriendLevel {
  const FriendLevel({
    required this.levelLabel,
    this.levelProgressFraction,
    this.avatarUrl = '',
  });

  final String levelLabel;

  /// 0.0..1.0, already converted from the backend's 0..100 percent and
  /// clamped. `null` means the backend didn't return a usable percent for
  /// this uid, distinct from a genuine resolved `0.0`.
  final double? levelProgressFraction;

  /// Raw, not-yet-sanitised avatar photo URL. Empty when the backend
  /// resolved no photo for this uid.
  final String avatarUrl;
}

/// Invokes the `getFriendLevels` callable for a batch of uids and returns its
/// raw response payload (or throws on transport/permission failure).
typedef GetFriendLevelsCallable = Future<Object?> Function(List<String> uids);

/// Repository-instance-scoped cache that resolves live friend levels for the
/// Firestore-sourced Friends / Requests / Blocked tabs.
///
/// Every resolve cycle ([resolveOverview]) starts by invalidating the cache
/// so a level-up or an admin-console XP/level correction is picked up on the
/// next load or live snapshot rather than being pinned forever; within one
/// cycle, uids shared across the friends/incoming/outgoing/blocked lists are
/// only fetched once. Any failure from the callable (offline,
/// permission-denied, a not-yet-deployed callable) is swallowed entirely: the
/// cache is left with whatever it already resolved, and every unresolved uid
/// falls back to its identity-mapped default, so the Friends screen always
/// renders and never throws.
class FriendLevelResolver {
  FriendLevelResolver(this._callable);

  final GetFriendLevelsCallable _callable;
  final Map<String, FriendLevel> _cache = <String, FriendLevel>{};

  static const int _chunkSize = 50;

  /// The cached live level for [uid], or `null` if none has been resolved.
  FriendLevel? lookup(String uid) => _cache[uid];

  /// Fetches and caches live levels for every uid in [uids] not already
  /// cached. Swallows every error from the callable so callers can always
  /// fall back to today's rendering.
  Future<void> ensureResolved(Iterable<String> uids) async {
    final missing = <String>{
      for (final uid in uids)
        if (!_cache.containsKey(uid)) uid,
    };
    if (missing.isEmpty) return;
    try {
      for (final chunk in chunkFriendLevelUids(missing.toList(growable: false))) {
        final raw = await _callable(chunk);
        _cache.addAll(parseFriendLevelsResponse(raw));
      }
    } catch (_) {
      // Offline, permission-denied, or a not-yet-deployed callable: leave the
      // cache untouched so every caller falls back to the identity-mapped
      // default (no live level, no pill).
    }
  }

  /// Clears every cached level.
  void invalidate() => _cache.clear();

  /// Invalidates the cache, resolves live levels for every distinct uid
  /// across [overview]'s four lists, and returns a copy of [overview] with
  /// resolved levels overlaid. A uid the resolver has no level for keeps its
  /// original (unresolved) model untouched.
  Future<FriendsOverviewReadModel> resolveOverview(
    FriendsOverviewReadModel overview,
  ) async {
    invalidate();
    final uids = <String>{
      for (final user in overview.friends) user.userId,
      for (final user in overview.incomingRequests) user.userId,
      for (final user in overview.outgoingRequests) user.userId,
      for (final user in overview.blockedUsers) user.userId,
    };
    await ensureResolved(uids);
    return FriendsOverviewReadModel(
      friends: _overlay(overview.friends),
      incomingRequests: _overlay(overview.incomingRequests),
      outgoingRequests: _overlay(overview.outgoingRequests),
      blockedUsers: _overlay(overview.blockedUsers),
    );
  }

  List<FriendUserReadModel> _overlay(List<FriendUserReadModel> users) {
    return users
        .map((user) {
          final level = lookup(user.userId);
          if (level == null) return user;
          return FriendUserReadModel(
            userId: user.userId,
            nickname: user.nickname,
            displayName: user.displayName,
            avatarInitials: user.avatarInitials,
            levelLabel: level.levelLabel,
            levelProgressFraction: level.levelProgressFraction,
            subtitleLabel: user.subtitleLabel,
            avatarUrl: level.avatarUrl,
          );
        })
        .toList(growable: false);
  }

  /// Splits [uids] into calls of at most [chunkSize] each. The backend caps
  /// `getFriendLevels` at 50 uids per invocation.
  @visibleForTesting
  static List<List<String>> chunkFriendLevelUids(
    List<String> uids, {
    int chunkSize = _chunkSize,
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

  /// Defensively parses a `getFriendLevels` response into [FriendLevel]s,
  /// skipping any entry that isn't shaped as documented. A uid the caller
  /// may not see is simply absent from the response, per the callable's
  /// contract, and stays absent from the returned map.
  @visibleForTesting
  static Map<String, FriendLevel> parseFriendLevelsResponse(Object? raw) {
    final result = <String, FriendLevel>{};
    if (raw is! Map<Object?, Object?>) return result;
    final levels = raw['levels'];
    if (levels is! Map<Object?, Object?>) return result;
    for (final entry in levels.entries) {
      final uid = entry.key;
      final value = entry.value;
      if (uid is! String || value is! Map<Object?, Object?>) continue;
      final label = value['levelLabel'];
      final percent = value['levelProgressPercent'];
      final avatarUrl = value['avatarUrl'];
      result[uid] = FriendLevel(
        levelLabel: label is String ? label : '',
        levelProgressFraction: percent is num
            ? (percent / 100).clamp(0.0, 1.0).toDouble()
            : null,
        avatarUrl: avatarUrl is String ? avatarUrl : '',
      );
    }
    return result;
  }
}
