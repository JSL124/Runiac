import '../../../core/formatting/relative_time.dart';
import '../domain/models/friends_read_model.dart';

/// Maps one Firestore friend/request/blocked edge document (or an equivalent
/// callable-result map) into a [FriendUserReadModel].
///
/// [requestDirection] must be passed as `'incoming'` or `'outgoing'` only for
/// rows sourced from the `friendRequests` owner list, together with the
/// row's already-resolved [requestCreatedAt] (the caller owns converting the
/// source Firestore `Timestamp`, keeping this file Firestore-free); together
/// they drive the Requests-tab subtitle ("Requested …ago" / "Sent …ago").
/// Leave [requestDirection] `null` for the Friends and Blocked tabs (and for
/// `searchFriends` results) so those rows keep rendering with no subtitle,
/// matching today's behaviour.
FriendUserReadModel? mapFriendIdentityDocument(
  Map<String, Object?> data, {
  String? fallbackUid,
  String? requestDirection,
  DateTime? requestCreatedAt,
  DateTime? now,
}) {
  final uid = friendStringValue(data['uid']) ?? fallbackUid;
  final nickname = friendStringValue(data['nickname']);
  final displayName = friendStringValue(data['displayName']);
  final avatarInitials = friendStringValue(data['avatarInitials']);
  if (uid == null ||
      uid.isEmpty ||
      nickname == null ||
      displayName == null ||
      avatarInitials == null ||
      displayName.isEmpty ||
      avatarInitials.isEmpty) {
    return null;
  }
  return FriendUserReadModel(
    userId: uid,
    nickname: nickname,
    displayName: displayName,
    avatarInitials: avatarInitials,
    levelLabel: friendLevelLabelValue(data['levelLabel']),
    levelProgressFraction: friendLevelProgressFractionValue(
      data['levelProgressPercent'],
    ),
    avatarUrl: friendAvatarUrlValue(data['avatarUrl']),
    subtitleLabel: requestDirection == null
        ? ''
        : friendRequestSubtitleLabel(
            direction: requestDirection,
            createdAt: requestCreatedAt,
            now: now,
          ),
  );
}

String? friendStringValue(Object? value) => value is String ? value : null;

/// Defensively reads an optional `levelLabel` field carried by enriched
/// sources (e.g. `searchFriends` results). Firestore edge documents never
/// carry this key, so an absent or non-String value keeps today's behaviour:
/// an empty label.
String friendLevelLabelValue(Object? value) => value is String ? value : '';

/// Defensively reads an optional `levelProgressPercent` field (0..100) and
/// converts it to a clamped 0.0..1.0 fraction. A missing or non-numeric value
/// stays `null` (unresolved), distinct from a genuine resolved `0.0`.
double? friendLevelProgressFractionValue(Object? value) {
  if (value is! num) return null;
  return (value / 100).clamp(0.0, 1.0).toDouble();
}

/// Defensively reads the optional `avatarUrl` carried by enriched sources.
///
/// The Friends, Requests, and Blocked tabs overlay their avatar from
/// `getFriendLevels` afterwards, so this only decides what the Search tab
/// shows — the one tab that never calls that resolver, having no social edge
/// to the runner yet. Firestore edge documents never carry the key, so an
/// absent or non-String value keeps today's behaviour: no photo, initials
/// disc. The value stays raw here and is sanitised at the render site, the
/// same as every other avatar URL the client transports.
String friendAvatarUrlValue(Object? value) => value is String ? value : '';

/// Builds the Requests-tab subtitle for one friend-request row: `'Requested
/// …ago'` for an incoming request, `'Sent …ago'` for an outgoing one. A
/// missing/invalid [createdAt] (already defensively resolved by the caller
/// from the source Firestore `Timestamp`) yields an empty subtitle so the
/// row renders exactly as it does today rather than showing misleading copy
/// (e.g. a spurious "56 years ago" from an epoch fallback).
String friendRequestSubtitleLabel({
  required String direction,
  required DateTime? createdAt,
  DateTime? now,
}) {
  if (createdAt == null) return '';
  final verb = direction == 'incoming' ? 'Requested' : 'Sent';
  return '$verb ${relativeAgoPhrase(createdAt, now: now)}';
}
