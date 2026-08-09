import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/models/active_challenge.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_badge_ownership.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_distance_format.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_history.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_invitation_summary.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_parse.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_parse_exception.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_tier.dart';

Map<String, Object?> _rulesMap({int targetMeters = 10000}) {
  return <String, Object?>{
    'tierId': '10K',
    'catalogVersion': 'challenge-distance-v1',
    'difficultyLabel': 'Beginner',
    'durationDays': 7,
    'durationMs': 604800000,
    'maxParticipants': 2,
    'maxInvitedFriends': 1,
    'targetMeters': targetMeters,
    'personalMinimumMeters': 3000,
  };
}

Map<String, Object?> _participant({
  required String uid,
  required String role,
  required String status,
  required int creditedMeters,
  String reward = 'NOT_ELIGIBLE',
}) {
  return <String, Object?>{
    'uid': uid,
    'role': role,
    'status': status,
    'creditedMeters': creditedMeters,
    'reward': reward,
    'displayNameSnapshot': 'Runner $uid',
    'avatarInitialsSnapshot': 'RR',
    'levelLabelSnapshot': 'Lv.4',
  };
}

Map<String, Object?> _challengeMap({
  int teamMeters = 10000,
  List<Map<String, Object?>>? participants,
}) {
  return <String, Object?>{
    'instance': <String, Object?>{
      'challengeId': 'c1',
      'ownerUid': 'u1',
      'tierId': '10K',
      'catalogVersion': 'challenge-distance-v1',
      'mode': 'GROUP',
      'status': 'ACTIVE',
      'rules': _rulesMap(),
      'rosterUids': <String>['u1', 'u2'],
      'maxParticipants': 2,
      'teamMeters': teamMeters,
      'createdAtMs': 100,
      'lobbyExpiresAtMs': 200,
      'startsAtMs': 300,
      'scheduledEndsAtMs': 400,
      'terminalReason': null,
    },
    'participants': participants ??
        <Map<String, Object?>>[
          _participant(
            uid: 'u1',
            role: 'owner',
            status: 'ACTIVE',
            creditedMeters: 6200,
          ),
          _participant(
            uid: 'u2',
            role: 'member',
            status: 'ACTIVE',
            creditedMeters: 3800,
          ),
        ],
  };
}

void main() {
  group('Challenge enum parsing', () {
    test('every server enum wire value parses through its exhaustive switch', () {
      for (final tier in ChallengeTierId.values) {
        expect(ChallengeTierId.parse(tier.wireValue), tier);
      }
      for (final mode in ChallengeMode.values) {
        expect(ChallengeMode.parse(mode.wireValue), mode);
      }
      for (final status in ChallengeInstanceStatus.values) {
        expect(ChallengeInstanceStatus.parse(status.wireValue), status);
      }
      for (final role in ChallengeParticipantRole.values) {
        expect(ChallengeParticipantRole.parse(role.wireValue), role);
      }
      for (final status in ChallengeParticipantStatus.values) {
        expect(ChallengeParticipantStatus.parse(status.wireValue), status);
      }
      for (final status in ChallengeInvitationStatus.values) {
        expect(ChallengeInvitationStatus.parse(status.wireValue), status);
      }
      for (final reward in ChallengeRewardStatus.values) {
        expect(ChallengeRewardStatus.parse(reward.wireValue), reward);
      }
      for (final reason in ChallengeTerminalReason.values) {
        expect(ChallengeTerminalReason.parse(reason.wireValue), reason);
      }
    });

    test('an unknown enum value raises a typed parse failure', () {
      expect(
        () => ChallengeTierId.parse('999K'),
        throwsA(isA<ChallengeParseException>()),
      );
      expect(
        () => ChallengeInstanceStatus.parse('PAUSED'),
        throwsA(isA<ChallengeParseException>()),
      );
      expect(
        () => ChallengeParticipantStatus.parse('QUIT'),
        throwsA(isA<ChallengeParseException>()),
      );
      expect(
        () => ChallengeTerminalReason.parse('BORED'),
        throwsA(isA<ChallengeParseException>()),
      );
    });
  });

  group('Strict primitive parsing', () {
    test('preserves integer metres and accepts whole-number doubles', () {
      expect(
        ChallengeParse.integer(<String, Object?>{'m': 62400}, 'm'),
        62400,
      );
      expect(
        ChallengeParse.integer(<String, Object?>{'m': 62400.0}, 'm'),
        62400,
      );
    });

    test('rejects fractional, missing, and wrong-typed values', () {
      expect(
        () => ChallengeParse.integer(<String, Object?>{'m': 62400.5}, 'm'),
        throwsA(isA<ChallengeParseException>()),
      );
      expect(
        () => ChallengeParse.integer(<String, Object?>{}, 'm'),
        throwsA(isA<ChallengeParseException>()),
      );
      expect(
        () => ChallengeParse.string(<String, Object?>{'s': 3}, 's'),
        throwsA(isA<ChallengeParseException>()),
      );
    });
  });

  group('Distance display formatting (display-only)', () {
    test('rounds integer metres to a one-decimal kilometre label', () {
      expect(ChallengeDistanceFormat.kilometresLabel(62400), '62.4 km');
      expect(ChallengeDistanceFormat.kilometresLabel(0), '0.0 km');
      expect(ChallengeDistanceFormat.kilometresLabel(1000000), '1000.0 km');
    });

    test('formats team progress as X.X / Y.Y km', () {
      expect(
        ChallengeDistanceFormat.teamProgressLabel(
          teamMetres: 10000,
          targetMetres: 42000,
        ),
        '10.0 / 42.0 km',
      );
    });
  });

  group('ChallengeCatalog parsing', () {
    test('maps soloTargetMeters into targetMeters and threads the version', () {
      final catalog = ChallengeCatalog.fromMap(<String, Object?>{
        'version': 'challenge-distance-v1',
        'tiers': <Map<String, Object?>>[
          <String, Object?>{
            'tierId': '42K',
            'difficultyLabel': 'Normal',
            'durationDays': 21,
            'durationMs': 1814400000,
            'maxParticipants': 3,
            'maxInvitedFriends': 2,
            'soloTargetMeters': 42000,
            'personalMinimumMeters': 7000,
          },
        ],
      });

      expect(catalog.version, 'challenge-distance-v1');
      expect(catalog.tiers.single.tierId, ChallengeTierId.k42);
      expect(catalog.tiers.single.targetMeters, 42000);
      expect(catalog.tiers.single.catalogVersion, 'challenge-distance-v1');
    });

    test('rejects a catalog entry with an unknown tier id', () {
      expect(
        () => ChallengeCatalog.fromMap(<String, Object?>{
          'version': 'challenge-distance-v1',
          'tiers': <Map<String, Object?>>[
            <String, Object?>{
              'tierId': '7K',
              'difficultyLabel': 'Nope',
              'durationDays': 1,
              'durationMs': 1,
              'maxParticipants': 2,
              'maxInvitedFriends': 1,
              'soloTargetMeters': 7000,
              'personalMinimumMeters': 1000,
            },
          ],
        }),
        throwsA(isA<ChallengeParseException>()),
      );
    });

    test('parses premiumOnlyTiers into tier ids', () {
      final catalog = ChallengeCatalog.fromMap(<String, Object?>{
        'version': 'challenge-distance-v1',
        'tiers': <Map<String, Object?>>[],
        'premiumOnlyTiers': <String>['100K', '1000K'],
      });

      expect(
        catalog.premiumOnlyTierIds,
        <ChallengeTierId>{ChallengeTierId.k100, ChallengeTierId.k1000},
      );
      expect(catalog.isPremiumOnly(ChallengeTierId.k100), isTrue);
      expect(catalog.isPremiumOnly(ChallengeTierId.k10), isFalse);
    });

    test('an absent premiumOnlyTiers field parses to the empty set', () {
      final catalog = ChallengeCatalog.fromMap(<String, Object?>{
        'version': 'challenge-distance-v1',
        'tiers': <Map<String, Object?>>[],
      });

      expect(catalog.premiumOnlyTierIds, isEmpty);
    });

    test(
      'skips unknown/non-string premiumOnlyTiers entries and never throws',
      () {
        // Additive contract: a server gating a tier id this client version
        // does not know must not break the catalog (fail-open lock UI).
        final catalog = ChallengeCatalog.fromMap(<String, Object?>{
          'version': 'challenge-distance-v1',
          'tiers': <Map<String, Object?>>[],
          'premiumOnlyTiers': <Object?>['200K', '7K', 42, null],
        });

        expect(
          catalog.premiumOnlyTierIds,
          <ChallengeTierId>{ChallengeTierId.k200},
        );
      },
    );

    test('a non-list premiumOnlyTiers value parses to the empty set', () {
      final catalog = ChallengeCatalog.fromMap(<String, Object?>{
        'version': 'challenge-distance-v1',
        'tiers': <Map<String, Object?>>[],
        'premiumOnlyTiers': 'not-a-list',
      });

      expect(catalog.premiumOnlyTierIds, isEmpty);
    });
  });

  group('ActiveChallenge parsing', () {
    test('reads the backend-clamped team metres verbatim (never recomputes)', () {
      // Participant credited metres sum to 15000, but the backend clamps the
      // exposed team total at the 10000 target. The model must honour the
      // clamped value, not re-sum the roster.
      final active = ActiveChallenge.fromChallengeMap(
        _challengeMap(
          teamMeters: 10000,
          participants: <Map<String, Object?>>[
            _participant(
              uid: 'u1',
              role: 'owner',
              status: 'ACTIVE',
              creditedMeters: 7000,
            ),
            _participant(
              uid: 'u2',
              role: 'member',
              status: 'ACTIVE',
              creditedMeters: 8000,
            ),
          ],
        ),
        currentUid: 'u1',
      );

      final rosterSum = active.participants
          .fold<int>(0, (sum, row) => sum + row.creditedMeters);
      expect(rosterSum, 15000);
      expect(active.teamMeters, 10000);
    });

    test('flags the current user and owner, and preserves rules metres', () {
      final active = ActiveChallenge.fromChallengeMap(
        _challengeMap(),
        currentUid: 'u1',
      );

      expect(active.status, ChallengeInstanceStatus.active);
      expect(active.mode, ChallengeMode.group);
      expect(active.isCurrentUserOwner, isTrue);
      expect(active.rules.targetMeters, 10000);
      expect(active.rules.personalMinimumMeters, 3000);
      expect(active.scheduledEndsAt,
          DateTime.fromMillisecondsSinceEpoch(400));
      final self = active.participants.firstWhere((row) => row.isCurrentUser);
      expect(self.uid, 'u1');
      expect(self.role, ChallengeParticipantRole.owner);
      expect(self.levelLabelSnapshot, 'Lv.4');
    });

    // Regression: a roster member whose profile carries no resolved level is
    // normal data — `level`/`levelLabel` reach `userProfiles/{uid}` only once a
    // run has awarded XP, so every runner who has never completed one resolves
    // to `""`. Parsing that strictly failed the WHOLE response, which is what
    // left the Challenge hub stuck on "Something went wrong. Please try again."
    // for every member of a lobby once such a runner joined.
    test('accepts a participant whose level label is empty', () {
      final map = _challengeMap(
        participants: <Map<String, Object?>>[
          _participant(uid: 'u1', role: 'owner', status: 'ACTIVE', creditedMeters: 5000),
          _participant(uid: 'u2', role: 'member', status: 'ACTIVE', creditedMeters: 0)
            ..['levelLabelSnapshot'] = '',
        ],
      );

      final active = ActiveChallenge.fromChallengeMap(map, currentUid: 'u1');

      final newcomer = active.participants.firstWhere((row) => row.uid == 'u2');
      expect(newcomer.levelLabelSnapshot, isEmpty);
      // The rest of the roster still parses, so the hub renders the lobby
      // instead of failing the whole view.
      expect(active.participants, hasLength(2));
      expect(
        active.participants.firstWhere((row) => row.uid == 'u1').levelLabelSnapshot,
        'Lv.4',
      );
    });

    test('accepts a participant whose level label is absent entirely', () {
      final map = _challengeMap(
        participants: <Map<String, Object?>>[
          _participant(uid: 'u1', role: 'owner', status: 'ACTIVE', creditedMeters: 5000)
            ..remove('levelLabelSnapshot'),
        ],
      );

      final active = ActiveChallenge.fromChallengeMap(map, currentUid: 'u1');

      expect(active.participants.single.levelLabelSnapshot, isEmpty);
    });

    test('rejects an instance missing a required field', () {
      final broken = _challengeMap();
      (broken['instance']! as Map<String, Object?>).remove('status');
      expect(
        () => ActiveChallenge.fromChallengeMap(broken, currentUid: 'u1'),
        throwsA(isA<ChallengeParseException>()),
      );
    });

    test('rejects an instance whose teamMeters is the wrong type', () {
      final broken = _challengeMap();
      (broken['instance']! as Map<String, Object?>)['teamMeters'] = '10000';
      expect(
        () => ActiveChallenge.fromChallengeMap(broken, currentUid: 'u1'),
        throwsA(isA<ChallengeParseException>()),
      );
    });
  });

  group('History, result, and badge ownership', () {
    test('projects a history entry into a terminal result verbatim', () {
      final entry = ChallengeHistoryEntry.fromMap(<String, Object?>{
        'challengeId': 'c9',
        'tierId': '10K',
        'mode': 'GROUP',
        'role': 'owner',
        'outcome': 'SUCCEEDED',
        'terminalReason': 'TARGET_REACHED',
        'teamMeters': 10000,
        'personalMeters': 6200,
        'targetMeters': 10000,
        'personalMinimumMeters': 3000,
        'startedAtMs': 1000,
        'endedAtMs': 5000,
      });

      final result = entry.toResult();
      expect(result.outcome, ChallengeParticipantStatus.succeeded);
      expect(result.tierId, ChallengeTierId.k10);
      expect(result.creditedMeters, 6200);
      expect(result.teamMeters, 10000);
      expect(result.startedAtMs, 1000);
      expect(result.endedAtMs, 5000);
      expect(result.earnedBadge, isTrue);
      expect(entry.personalMinimumReachedForDisplay, isTrue);
    });

    test('parses badge ownership from tier id list and reports ownership', () {
      final ownership = ChallengeBadgeOwnership.fromTierIds(
        <Object?>['10K', '42K'],
      );
      expect(ownership.isOwned(ChallengeTierId.k10), isTrue);
      expect(ownership.isOwned(ChallengeTierId.k42), isTrue);
      expect(ownership.isOwned(ChallengeTierId.k100), isFalse);
    });

    test('rejects a malformed badge ownership payload', () {
      expect(
        () => ChallengeBadgeOwnership.fromTierIds(<Object?>[42]),
        throwsA(isA<ChallengeParseException>()),
      );
      expect(
        () => ChallengeBadgeOwnership.fromTierIds(<Object?>['nope']),
        throwsA(isA<ChallengeParseException>()),
      );
    });
  });

  group('ChallengeInvitationSummary parsing', () {
    test('treats a getChallengeInvitations entry as pending', () {
      final summary = ChallengeInvitationSummary.fromPendingView(
        <String, Object?>{
          'inviteId': 'c1__u2',
          'challengeId': 'c1',
          'tierId': '10K',
          'ownerUid': 'u1',
          'createdAtMs': 100,
          'expiresAtMs': 200,
          'rules': _rulesMap(),
        },
      );

      expect(summary.status, ChallengeInvitationStatus.pending);
      expect(summary.tierId, ChallengeTierId.k10);
      expect(summary.rules?.targetMeters, 10000);
      expect(summary.expiresAt, DateTime.fromMillisecondsSinceEpoch(200));
    });
  });
}
