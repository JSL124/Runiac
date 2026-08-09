import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/friends/data/firebase_friends_repository.dart';
import 'package:runiac_app/features/friends/data/friend_identity_mapper.dart'
    show friendRequestSubtitleLabel;
import 'package:runiac_app/features/friends/data/friends_owner_list_reader.dart'
    show friendRequestCreatedAtValue;

void main() {
  test('owner-list reads keep the Rules-required bounded query', () {
    final repositorySource = File(
      'lib/features/friends/data/firebase_friends_repository.dart',
    ).readAsStringSync();
    final readerSource = File(
      'lib/features/friends/data/friends_owner_list_reader.dart',
    ).readAsStringSync();

    expect(
      readerSource,
      contains(
        ".orderBy('listSortTieBreaker')\n      .limit(30)\n      .get()",
      ),
    );
    expect(repositorySource, contains("user.collection('friends')"));
    expect(repositorySource, contains("user.collection('friendRequests')"));
    expect(repositorySource, contains("user.collection('blockedUsers')"));
  });

  test('live owner-list watch keeps the same bounded query as the read', () {
    final readerSource = File(
      'lib/features/friends/data/friends_owner_list_reader.dart',
    ).readAsStringSync();

    expect(
      readerSource,
      contains(
        ".orderBy('listSortTieBreaker')\n      .limit(30)\n      .snapshots()",
      ),
    );
    expect(readerSource, contains('watchFriendsOwnerList'));
  });

  test('maps the finalized root-level owner-list document shape', () {
    final user = mapFriendIdentityDocument(<String, Object?>{
      'uid': 'runner-b',
      'nickname': 'grace-teo',
      'displayName': 'Grace Teo',
      'avatarInitials': 'GT',
      'listSortKey': 'grace-teo',
      'listSortTieBreaker': 'runner-b',
    });

    expect(user?.userId, 'runner-b');
    expect(user?.nickname, 'grace-teo');
    expect(user?.displayName, 'Grace Teo');
    expect(user?.avatarInitials, 'GT');
    // A Firestore edge document never carries an avatar; the Friends,
    // Requests, and Blocked tabs overlay theirs from `getFriendLevels`.
    expect(user?.avatarUrl, '');
  });

  test('carries the avatar an enriched searchFriends result supplies', () {
    const photoUrl =
        'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fgt.png?alt=media&token=tok';
    // The Search tab is the one tab that never calls `getFriendLevels` — it
    // has no social edge to the runner yet — so the callable's own payload is
    // the only chance its row gets to show a photo.
    final user = mapFriendIdentityDocument(<String, Object?>{
      'uid': 'runner-b',
      'nickname': 'grace-teo',
      'displayName': 'Grace Teo',
      'avatarInitials': 'GT',
      'levelProgressPercent': 42,
      'avatarUrl': photoUrl,
    });

    expect(user?.avatarUrl, photoUrl);
    expect(user?.levelProgressFraction, closeTo(0.42, 1e-9));
  });

  test('tolerates a non-String avatarUrl from an older backend revision', () {
    final user = mapFriendIdentityDocument(<String, Object?>{
      'uid': 'runner-b',
      'nickname': 'grace-teo',
      'displayName': 'Grace Teo',
      'avatarInitials': 'GT',
      'avatarUrl': 42,
    });

    expect(user?.avatarUrl, '');
  });

  test('an incoming request row renders a "Requested …ago" subtitle', () {
    final now = DateTime(2026, 7, 21, 12, 0, 0);
    final createdAt = now.subtract(const Duration(days: 3));
    final user = mapFriendIdentityDocument(<String, Object?>{
      'uid': 'runner-b',
      'nickname': 'grace-teo',
      'displayName': 'Grace Teo',
      'avatarInitials': 'GT',
    }, requestDirection: 'incoming', requestCreatedAt: createdAt, now: now);

    expect(
      friendRequestSubtitleLabel(
        direction: 'incoming',
        createdAt: createdAt,
        now: now,
      ),
      'Requested 3 days ago',
    );
    expect(user?.subtitleLabel, 'Requested 3 days ago');
  });

  test('an outgoing request row renders a "Sent …ago" subtitle', () {
    final now = DateTime(2026, 7, 21, 12, 0, 0);
    final createdAt = now.subtract(const Duration(days: 3));
    final user = mapFriendIdentityDocument(<String, Object?>{
      'uid': 'runner-b',
      'nickname': 'grace-teo',
      'displayName': 'Grace Teo',
      'avatarInitials': 'GT',
    }, requestDirection: 'outgoing', requestCreatedAt: createdAt, now: now);

    expect(
      friendRequestSubtitleLabel(
        direction: 'outgoing',
        createdAt: createdAt,
        now: now,
      ),
      'Sent 3 days ago',
    );
    expect(user?.subtitleLabel, 'Sent 3 days ago');
  });

  test(
    'a missing or non-Timestamp createdAt yields an empty request subtitle',
    () {
      final missing = mapFriendIdentityDocument(<String, Object?>{
        'uid': 'runner-b',
        'nickname': 'grace-teo',
        'displayName': 'Grace Teo',
        'avatarInitials': 'GT',
      }, requestDirection: 'incoming');
      expect(missing?.subtitleLabel, '');

      expect(friendRequestCreatedAtValue(null), isNull);
      expect(friendRequestCreatedAtValue('2026-07-01T00:00:00Z'), isNull);
      expect(friendRequestCreatedAtValue(1234567890), isNull);

      final resolved = friendRequestCreatedAtValue(
        Timestamp.fromDate(DateTime(2026, 7, 1)),
      );
      expect(resolved, DateTime(2026, 7, 1));

      expect(
        friendRequestSubtitleLabel(direction: 'incoming', createdAt: null),
        '',
      );
    },
  );

  test(
    'a future createdAt does not render a negative duration subtitle',
    () {
      final now = DateTime(2026, 7, 21, 12, 0, 0);
      final label = friendRequestSubtitleLabel(
        direction: 'incoming',
        createdAt: now.add(const Duration(days: 2)),
        now: now,
      );
      expect(label, 'Requested just now');
    },
  );

  test(
    'Friends and Blocked rows (no requestDirection) keep an empty subtitle',
    () {
      final friend = mapFriendIdentityDocument(<String, Object?>{
        'uid': 'runner-b',
        'nickname': 'grace-teo',
        'displayName': 'Grace Teo',
        'avatarInitials': 'GT',
      }, requestCreatedAt: DateTime.now());
      expect(friend?.subtitleLabel, '');
    },
  );

  test('does not read an obsolete nested identity map', () {
    final user = mapFriendIdentityDocument(<String, Object?>{
      'identity': <String, Object?>{
        'uid': 'runner-b',
        'nickname': 'grace-teo',
        'displayName': 'Grace Teo',
        'avatarInitials': 'GT',
      },
    }, fallbackUid: 'runner-b');

    expect(user, isNull);
  });

  test('maps exact backend authentication and argument reasons', () {
    expect(
      mapFriendsCallableError(
        transportCode: 'internal',
        details: const <String, Object?>{'reason': 'UNAUTHENTICATED'},
      ).code,
      FriendsRepositoryErrorCode.authRequired,
    );
    expect(
      mapFriendsCallableError(
        transportCode: 'internal',
        details: const <String, Object?>{'reason': 'INVALID_ARGUMENT'},
      ).code,
      FriendsRepositoryErrorCode.invalidRequest,
    );
  });

  test('unknown backend reason falls back to the transport code', () {
    expect(
      mapFriendsCallableError(
        transportCode: 'unauthenticated',
        details: const <String, Object?>{'reason': 'UNKNOWN_REASON'},
      ).code,
      FriendsRepositoryErrorCode.authRequired,
    );
    expect(
      mapFriendsCallableError(
        transportCode: 'invalid-argument',
        details: const <String, Object?>{'reason': 'UNKNOWN_REASON'},
      ).code,
      FriendsRepositoryErrorCode.invalidRequest,
    );
  });

  test('signed-in Firestore permission failures stay privacy-safe', () {
    expect(
      mapFriendsFirestoreError('permission-denied').code,
      FriendsRepositoryErrorCode.unavailable,
    );
  });
}
