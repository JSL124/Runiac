import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/data/firebase_challenge_repository.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_rules_snapshot.dart';
import 'package:runiac_app/features/challenge/domain/repositories/challenge_repository.dart';

/// Unit coverage for the two pure hybrid-seed mapping functions the
/// realtime Challenge repository uses ([mapActiveChallengeView],
/// [mapPendingInvitationViews]), plus a source-shape check on the Firestore
/// read store's bounded/no-orderBy invitation query.
///
/// These pure functions carry the entire seeding contract: level labels and
/// per-tier rules are captured once from a `getActiveChallenge` /
/// `getChallengeInvitations` callable result and held fixed as the live
/// snapshot stream (built and tested separately in the widget suite) emits
/// membership/status/metres changes.
void main() {
  group('mapActiveChallengeView', () {
    test('returns null for a null view', () {
      expect(
        mapActiveChallengeView(
          null,
          levelLabelSeed: const <String, String>{},
          currentUid: 'uidA',
        ),
        isNull,
      );
    });

    test(
      'keeps the seeded label for a known uid and blanks an unseeded one, '
      'unaffected by a later roster change',
      () {
        final seed = const <String, String>{'uidA': 'Lv.5'};

        final view1 = _view(
          instance: _instanceView(rosterUids: const <String>['uidA', 'uidB']),
          participants: <Map<String, Object?>>[
            _participantView(uid: 'uidA', role: 'owner', meters: 100),
            _participantView(uid: 'uidB', role: 'member', meters: 50),
          ],
        );
        final active1 = mapActiveChallengeView(
          view1,
          levelLabelSeed: seed,
          currentUid: 'uidA',
        )!;
        final rowA1 = active1.participants.firstWhere((r) => r.uid == 'uidA');
        final rowB1 = active1.participants.firstWhere((r) => r.uid == 'uidB');

        expect(rowA1.levelLabelSnapshot, 'Lv.5');
        expect(rowB1.levelLabelSnapshot.trim(), isEmpty);
        // Membership/headcount/status/metres are parsed live from the raw
        // view, not fabricated by the seed.
        expect(active1.rosterUids, <String>['uidA', 'uidB']);
        expect(rowA1.creditedMeters, 100);
        expect(rowB1.creditedMeters, 50);
        expect(rowA1.status, ChallengeParticipantStatus.active);

        // A later emission adds a third participant. The seed was built once
        // from the callable seed and is never recomputed from a snapshot, so
        // uidA still reads 'Lv.5' and the newcomer also renders blank.
        final view2 = _view(
          instance:
              _instanceView(rosterUids: const <String>['uidA', 'uidB', 'uidC']),
          participants: <Map<String, Object?>>[
            _participantView(uid: 'uidA', role: 'owner', meters: 150),
            _participantView(uid: 'uidB', role: 'member', meters: 90),
            _participantView(uid: 'uidC', role: 'member', meters: 10),
          ],
        );
        final active2 = mapActiveChallengeView(
          view2,
          levelLabelSeed: seed,
          currentUid: 'uidA',
        )!;
        final rowA2 = active2.participants.firstWhere((r) => r.uid == 'uidA');
        final rowC2 = active2.participants.firstWhere((r) => r.uid == 'uidC');

        expect(rowA2.levelLabelSnapshot, 'Lv.5');
        expect(rowC2.levelLabelSnapshot.trim(), isEmpty);
        expect(active2.rosterUids, <String>['uidA', 'uidB', 'uidC']);
        expect(rowA2.creditedMeters, 150);
      },
    );

    test(
      'keeps the seeded avatar for a known uid and blanks an unseeded one, '
      'the same hybrid treatment as the level label',
      () {
        final avatarSeed = const <String, String>{
          'uidA':
              'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok',
        };

        final view = _view(
          instance: _instanceView(rosterUids: const <String>['uidA', 'uidB']),
          participants: <Map<String, Object?>>[
            _participantView(uid: 'uidA', role: 'owner', meters: 100),
            _participantView(uid: 'uidB', role: 'member', meters: 50),
          ],
        );
        final active = mapActiveChallengeView(
          view,
          levelLabelSeed: const <String, String>{},
          avatarUrlSeed: avatarSeed,
          currentUid: 'uidA',
        )!;
        final rowA = active.participants.firstWhere((r) => r.uid == 'uidA');
        final rowB = active.participants.firstWhere((r) => r.uid == 'uidB');

        expect(
          rowA.avatarUrlSnapshot,
          'https://firebasestorage.googleapis.com/v0/b/bucket/o/avatars%2Fabc.png?alt=media&token=tok',
        );
        expect(rowB.avatarUrlSnapshot, '');
      },
    );

    test(
      'defaults every participant\'s avatar to empty when no seed is given',
      () {
        final view = _view(
          instance: _instanceView(rosterUids: const <String>['uidA']),
          participants: <Map<String, Object?>>[
            _participantView(uid: 'uidA', role: 'owner', meters: 100),
          ],
        );
        final active = mapActiveChallengeView(
          view,
          levelLabelSeed: const <String, String>{},
          currentUid: 'uidA',
        )!;

        expect(active.participants.single.avatarUrlSnapshot, '');
      },
    );

    test(
      'keeps the seeded level progress for a known uid and zeroes an unseeded one',
      () {
        final view = _view(
          instance: _instanceView(rosterUids: const <String>['uidA', 'uidB']),
          participants: <Map<String, Object?>>[
            _participantView(uid: 'uidA', role: 'owner', meters: 100),
            _participantView(uid: 'uidB', role: 'member', meters: 50),
          ],
        );
        final active = mapActiveChallengeView(
          view,
          levelLabelSeed: const <String, String>{},
          levelProgressPercentSeed: const <String, int>{'uidA': 64},
          currentUid: 'uidA',
        )!;

        expect(
          active.participants
              .firstWhere((r) => r.uid == 'uidA')
              .levelProgressPercentSnapshot,
          64,
        );
        expect(
          active.participants
              .firstWhere((r) => r.uid == 'uidB')
              .levelProgressPercentSnapshot,
          0,
        );
      },
    );

    test(
      'clamps a corrupt stored level progress instead of overdrawing the ring',
      () {
        final view = _view(
          instance: _instanceView(rosterUids: const <String>['uidA']),
          participants: <Map<String, Object?>>[
            _participantView(uid: 'uidA', role: 'owner', meters: 100),
          ],
        );
        final active = mapActiveChallengeView(
          view,
          levelLabelSeed: const <String, String>{},
          levelProgressPercentSeed: const <String, int>{'uidA': 140},
          currentUid: 'uidA',
        )!;

        expect(active.participants.single.levelProgressPercentSnapshot, 100);
      },
    );

    test('wraps a malformed view as INVALID_RESPONSE', () {
      final broken = _view(
        instance: _instanceView(),
        participants: <Map<String, Object?>>[
          <String, Object?>{'uid': 'uidA'}, // missing required fields
        ],
      );
      expect(
        () => mapActiveChallengeView(
          broken,
          levelLabelSeed: const <String, String>{},
          currentUid: 'uidA',
        ),
        throwsA(
          isA<ChallengeFailure>()
              .having((f) => f.reason, 'reason', 'INVALID_RESPONSE'),
        ),
      );
    });
  });

  group('mapPendingInvitationViews', () {
    final tierRules = const ChallengeRulesSnapshot(
      tierId: ChallengeTierId.k42,
      catalogVersion: 'challenge-distance-v1',
      difficultyLabel: 'Normal',
      durationDays: 21,
      durationMs: 1814400000,
      maxParticipants: 3,
      maxInvitedFriends: 2,
      targetMeters: 42000,
      personalMinimumMeters: 7000,
    );

    test('seeds rules for a known tier, nulls an unseeded tier, keeps order', () {
      final views = <Map<String, Object?>>[
        <String, Object?>{
          'inviteId': 'i2',
          'challengeId': 'c2',
          'tierId': '42K',
          'ownerUid': 'friend',
          'createdAtMs': 2000,
          'expiresAtMs': 9000,
        },
        <String, Object?>{
          'inviteId': 'i1',
          'challengeId': 'c1',
          'tierId': '10K',
          'ownerUid': 'friend',
          'createdAtMs': 1000,
          'expiresAtMs': 9000,
        },
      ];
      final rulesSeed = <ChallengeTierId, ChallengeRulesSnapshot>{
        ChallengeTierId.k42: tierRules,
      };

      final summaries =
          mapPendingInvitationViews(views, rulesSeed: rulesSeed);

      // Newest-first order (as handed in by the store) is preserved, not
      // re-sorted here.
      expect(summaries.map((s) => s.inviteId).toList(), <String>['i2', 'i1']);
      expect(summaries[0].tierId, ChallengeTierId.k42);
      expect(summaries[0].rules, isNotNull);
      expect(summaries[0].rules!.targetMeters, 42000);
      expect(summaries[1].tierId, ChallengeTierId.k10);
      expect(summaries[1].rules, isNull);
      expect(
        summaries.every((s) => s.status == ChallengeInvitationStatus.pending),
        isTrue,
      );
    });

    test('wraps a malformed view as INVALID_RESPONSE', () {
      expect(
        () => mapPendingInvitationViews(
          <Map<String, Object?>>[
            <String, Object?>{'inviteId': 'i1'}, // missing required fields
          ],
          rulesSeed: const <ChallengeTierId, ChallengeRulesSnapshot>{},
        ),
        throwsA(
          isA<ChallengeFailure>()
              .having((f) => f.reason, 'reason', 'INVALID_RESPONSE'),
        ),
      );
    });
  });

  group('firestore_challenge_read_store source shape', () {
    test(
      'bounds the participants and pending-invitations watch queries and '
      'keeps the invitations watch free of orderBy',
      () {
        final source = File(
          'lib/features/challenge/data/firestore_challenge_read_store.dart',
        ).readAsStringSync();

        expect(source, contains('.limit(_participantsLimit)'));
        expect(source, contains('.limit(_invitationsLimit)'));

        final invitationsStart = source.indexOf(
          'Stream<List<Map<String, Object?>>> watchPendingInvitationViews',
        );
        final activeStart = source.indexOf(
          'Stream<Map<String, Object?>?> watchActiveChallengeView',
        );
        expect(invitationsStart, greaterThanOrEqualTo(0));
        expect(activeStart, greaterThan(invitationsStart));
        final invitationsSegment =
            source.substring(invitationsStart, activeStart);

        // Assert the actual query API is absent (a code comment in the store
        // legitimately mentions the word orderBy, so match the call syntax).
        expect(invitationsSegment, isNot(contains('.orderBy(')));
        expect(invitationsSegment, contains("isEqualTo: ownerUid"));
        expect(invitationsSegment, contains("isEqualTo: 'PENDING'"));
      },
    );
  });
}

Map<String, Object?> _rulesMap({
  String tierId = '10K',
  int durationDays = 7,
  int durationMs = 604800000,
  int maxParticipants = 2,
  int maxInvitedFriends = 1,
  int targetMeters = 10000,
  int personalMinimumMeters = 3000,
}) {
  return <String, Object?>{
    'tierId': tierId,
    'catalogVersion': 'challenge-distance-v1',
    'difficultyLabel': 'Beginner',
    'durationDays': durationDays,
    'durationMs': durationMs,
    'maxParticipants': maxParticipants,
    'maxInvitedFriends': maxInvitedFriends,
    'targetMeters': targetMeters,
    'personalMinimumMeters': personalMinimumMeters,
  };
}

Map<String, Object?> _participantView({
  required String uid,
  String role = 'owner',
  String status = 'ACTIVE',
  int meters = 0,
  String reward = 'NOT_ELIGIBLE',
  String name = 'Runner',
  String initials = 'RU',
}) {
  return <String, Object?>{
    'uid': uid,
    'role': role,
    'status': status,
    'creditedMeters': meters,
    'reward': reward,
    'displayNameSnapshot': name,
    'avatarInitialsSnapshot': initials,
  };
}

Map<String, Object?> _instanceView({
  String challengeId = 'ch-1',
  String ownerUid = 'uidA',
  String status = 'ACTIVE',
  String mode = 'GROUP',
  int teamMeters = 0,
  List<String> rosterUids = const <String>['uidA', 'uidB'],
  Map<String, Object?>? rules,
}) {
  return <String, Object?>{
    'challengeId': challengeId,
    'ownerUid': ownerUid,
    'tierId': '10K',
    'catalogVersion': 'challenge-distance-v1',
    'mode': mode,
    'status': status,
    'rules': rules ?? _rulesMap(),
    'rosterUids': rosterUids,
    'maxParticipants': 2,
    'teamMeters': teamMeters,
    'createdAtMs': 1000,
    'lobbyExpiresAtMs': 2000,
    'startsAtMs': null,
    'scheduledEndsAtMs': null,
    'terminalReason': null,
  };
}

Map<String, Object?> _view({
  required Map<String, Object?> instance,
  required List<Map<String, Object?>> participants,
}) {
  return <String, Object?>{'instance': instance, 'participants': participants};
}
