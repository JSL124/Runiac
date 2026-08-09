import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/data/static_challenge_repository.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/repositories/challenge_repository.dart';

void main() {
  group('StaticChallengeRepository state coverage', () {
    const expectedStatus = <ChallengeScenarioSeed, ChallengeInstanceStatus?>{
      ChallengeScenarioSeed.none: null,
      ChallengeScenarioSeed.recruiting: ChallengeInstanceStatus.recruiting,
      ChallengeScenarioSeed.active: ChallengeInstanceStatus.active,
      ChallengeScenarioSeed.settling: ChallengeInstanceStatus.settling,
      ChallengeScenarioSeed.succeeded: ChallengeInstanceStatus.succeeded,
      ChallengeScenarioSeed.failed: ChallengeInstanceStatus.failed,
      ChallengeScenarioSeed.cancelled: ChallengeInstanceStatus.cancelled,
      ChallengeScenarioSeed.left: ChallengeInstanceStatus.active,
    };

    test('covers every seeded lifecycle state', () async {
      for (final entry in expectedStatus.entries) {
        final repository = StaticChallengeRepository(seed: entry.key);
        final active = await repository.activeChallenge();
        if (entry.value == null) {
          expect(active, isNull, reason: '${entry.key}');
        } else {
          expect(active, isNotNull, reason: '${entry.key}');
          expect(active!.status, entry.value, reason: '${entry.key}');
        }
      }
    });

    test('settling seed signals the calculating branch', () async {
      const repository = StaticChallengeRepository(
        seed: ChallengeScenarioSeed.settling,
      );
      final active = await repository.activeChallenge();
      expect(active!.isSettling, isTrue);
    });

    test('left seed marks the current user as departed and non-owner', () async {
      const repository = StaticChallengeRepository(
        seed: ChallengeScenarioSeed.left,
      );
      final active = await repository.activeChallenge();
      final self = active!.participants.firstWhere((row) => row.isCurrentUser);
      expect(self.hasLeft, isTrue);
      expect(active.isCurrentUserOwner, isFalse);
    });

    test('exposes the full nine-tier catalog with distinct tiers', () async {
      const repository = StaticChallengeRepository();
      final catalog = await repository.catalog();
      expect(catalog.tiers, hasLength(9));
      expect(
        catalog.tiers.map((tier) => tier.tierId).toSet(),
        ChallengeTierId.values.toSet(),
      );
      for (final tier in catalog.tiers) {
        expect(tier.targetMeters, greaterThan(0));
        expect(tier.personalMinimumMeters, greaterThan(0));
      }
    });

    test('returns read models for invitations, history, and badges', () async {
      const repository = StaticChallengeRepository();
      expect(await repository.invitations(), isNotEmpty);
      expect(await repository.history(), isNotEmpty);
      final badges = await repository.ownedBadges();
      expect(badges.isOwned(ChallengeTierId.k10), isTrue);
    });

    test('command callables return deterministic results', () async {
      const repository = StaticChallengeRepository();
      final created = await repository.createLobby(ChallengeTierId.k10);
      expect(created.status, ChallengeInstanceStatus.recruiting);
      final started = await repository.start(challengeId: 'x');
      expect(started.scheduledEndsAtMs, greaterThan(started.startsAtMs));
      final left = await repository.leave(challengeId: 'x');
      expect(left.challengeId, 'x');
    });

    test('surfaces a typed ChallengeFailure sentinel reason', () {
      expect(ChallengeFailure.unavailableReason, 'CHALLENGE_UNAVAILABLE');
    });
  });

  group('Challenge feature backend-trust boundary', () {
    late final String source;

    setUpAll(() {
      source = _challengeFeatureSourceWithoutComments();
    });

    test('contains no Firestore data or write access path', () {
      const forbiddenFirestoreTokens = <String>[
        'package:cloud_firestore',
        'cloud_firestore',
        'FirebaseFirestore',
        'CollectionReference',
        'DocumentReference',
        'QuerySnapshot',
        'DocumentSnapshot',
        'WriteBatch',
        'Transaction',
        '.collection(',
        '.collectionGroup(',
        '.doc(',
        '.snapshots(',
      ];
      for (final token in forbiddenFirestoreTokens) {
        expect(source, isNot(contains(token)), reason: token);
      }
    });

    test('contains no write path to trusted challenge documents', () {
      const forbiddenWriteTokens = <String>[
        '.set(',
        '.update(',
        '.delete(',
        'runTransaction',
        'writeBatch',
        '.batch(',
        'FieldValue',
      ];
      for (final token in forbiddenWriteTokens) {
        expect(source, isNot(contains(token)), reason: token);
      }
    });

    test('writes nothing but the ceremony seen-marker', () {
      // The one Challenge file excluded from the write scan above, held to the
      // single document and single field it exists for. A write reaching any
      // trusted challenge collection — history, badges, instances, grants —
      // fails here.
      final seenStore = _removeDartComments(
        File(
          'lib/features/challenge/data/'
          'firestore_challenge_result_seen_store.dart',
        ).readAsStringSync(),
      );

      expect(seenStore, contains("collection('challengeState')"));
      expect(seenStore, contains("'lastSeenResultEndedAtMs'"));
      for (final trustedCollection in <String>[
        'challengeHistory',
        'challengeBadges',
        'challengeInstances',
        'challengeRewardGrants',
        'challengeInvitations',
        'challengeSlots',
        'participants',
      ]) {
        expect(seenStore, isNot(contains(trustedCollection)));
      }
      // One write shape only: no delete, no batch, no transaction, no
      // server-side field mutation.
      expect(seenStore, isNot(contains('.delete(')));
      expect(seenStore, isNot(contains('.update(')));
      expect(seenStore, isNot(contains('FieldValue')));
      expect(seenStore, isNot(contains('runTransaction')));
      expect(seenStore, isNot(contains('.batch(')));
    });

    test('performs no client-side target/eligibility/reward calculation', () {
      const forbiddenCalculationVerbs = <String>[
        'calculate',
        'derive',
        'aggregate',
        'validate',
        'award',
        'increment',
        'publish',
        'approve',
        'reject',
        'suspend',
      ];
      for (final verb in forbiddenCalculationVerbs) {
        expect(
          source,
          isNot(contains(RegExp('\\b$verb\\b'))),
          reason: verb,
        );
      }
    });
  });
}

String _challengeFeatureSourceWithoutComments() {
  // The approved Firestore adapters, both separately allowlisted in
  // `backend_owned_contract_test.dart`; the trust-boundary scan below excludes
  // them so every OTHER Challenge file stays Firestore-free.
  //
  //  - the member-scoped read adapter for the two read paths without a callable
  //    (durable history, badge ownership);
  //  - the result-ceremony seen-marker, the one Challenge document the client
  //    writes. It is presentation state, not trusted state, and the dedicated
  //    test below pins it to that single field and path so this exclusion
  //    cannot quietly widen into a write path onto trusted challenge data.
  const approvedFirestoreAdapters = <String>{
    'lib/features/challenge/data/firestore_challenge_read_store.dart',
    'lib/features/challenge/data/firestore_challenge_result_seen_store.dart',
  };
  final files = Directory('lib/features/challenge')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where(
        (file) => !approvedFirestoreAdapters.contains(
          file.path.replaceAll(r'\', '/'),
        ),
      )
      .toList()
    ..sort((left, right) => left.path.compareTo(right.path));
  final buffer = StringBuffer();
  for (final file in files) {
    buffer.writeln(_removeDartComments(file.readAsStringSync()));
  }
  return buffer.toString();
}

String _removeDartComments(String source) {
  return source
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
      .replaceAll(RegExp(r'//.*', multiLine: true), '');
}
