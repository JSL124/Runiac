import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/data/firestore_user_profile_persistence_repository.dart';
import 'package:runiac_app/features/profile/domain/repositories/user_profile_persistence_repository.dart';

void main() {
  test(
    'concrete writer uses non-mutating availability and upsert callables',
    () async {
      final calls = <String>[];
      final writer = FirestoreUserProfileDocumentWriter(
        callable: (name, payload) async {
          calls.add('$name:${payload['nickname']}');
          return <String, Object?>{
            'available': true,
            'identity': <String, Object?>{
              'uid': 'test-auth-user-1',
              'nickname': payload['nickname'],
              'displayName': payload['nickname'],
              'avatarInitials': 'ER',
            },
          };
        },
      );

      expect(
        await writer.isNicknameAvailable(
          uid: 'test-auth-user-1',
          nickname: 'Élodie Runner',
        ),
        isTrue,
      );
      await writer.upsertNickname(
        uid: 'test-auth-user-1',
        nickname: 'Élodie Runner',
      );

      expect(calls, <String>[
        'checkNicknameAvailability:Élodie Runner',
        'upsertNickname:Élodie Runner',
      ]);
    },
  );

  test(
    'concrete writer maps a nickname collision to neutral unavailable',
    () async {
      final writer = FirestoreUserProfileDocumentWriter(
        callable: (name, payload) async {
          throw FirebaseFunctionsException(
            code: 'invalid-argument',
            message: 'nickname unavailable',
            details: const <String, Object?>{'reason': 'NICKNAME_UNAVAILABLE'},
          );
        },
      );

      expect(
        () => writer.upsertNickname(uid: 'test-auth-user-1', nickname: 'Maya'),
        throwsA(isA<NicknameUnavailableException>()),
      );
    },
  );

  test(
    'nickname validation counts Unicode code points and keeps initials rune-safe',
    () {
      final thirtyEmoji = List.filled(30, '😀').join();
      final thirtyOneEmoji = List.filled(31, '😀').join();
      expect(PersonalProfileDraft.validateNickname(thirtyEmoji), isNull);
      expect(PersonalProfileDraft.validateNickname(thirtyOneEmoji), isNotNull);
      expect(PersonalProfileDraft.validateNickname('Runner\u007F'), isNotNull);

      final draft = PersonalProfileDraft(
        fullName: 'Runner',
        nickname: '😀 Runner',
        dateOfBirthIso: '2000-01-01',
        weightKg: 59,
        locationLabel: 'Orchard, Singapore',
      );
      expect(draft.avatarInitials, '😀R');
    },
  );

  group('UserProfileOnboardingSnapshot', () {
    test('serializes only client-owned onboarding profile fields', () {
      final snapshot = UserProfileOnboardingSnapshot(
        displayName: 'Maya',
        fullName: 'Maya Tan',
        nickname: 'Maya',
        avatarInitials: 'M',
        dateOfBirthIso: '2002-06-28',
        ageYears: 24,
        weightKg: 58.5,
        locationLabel: 'Queenstown, Singapore',
        fitnessLevel: 'new',
        goals: const <String>['habit'],
        availability: const <String, Object>{
          'weeklySessions': '3',
          'preferredDays': <String>['Mon', 'Wed', 'Fri'],
          'preferredTime': 'morning',
          'sessionLengthMinutes': '20',
        },
        planCautiousness: 'balanced',
        healthSafetyReadiness: const <String, Object>{
          'comfort': 'ready',
          'activitySymptoms': <String>['none'],
          'recentRunningConsistency': 'none',
          'currentWeeklyRunFrequency': '0',
          'continuousRunCapacity': 'walk',
          'runningPlace': 'park',
          'motivationStyle': 'reminders',
        },
      );

      final document = snapshot.toFirestoreDocument(updatedAt: 1);

      expect(document.keys, <String>[
        'fullName',
        'dateOfBirth',
        'ageYears',
        'weightKg',
        'locationLabel',
        'fitnessLevel',
        'goals',
        'availability',
        'planCautiousness',
        'healthSafetyReadiness',
        'updatedAt',
      ]);
      expect(document, isNot(containsPair('xp', anything)));
      expect(document, isNot(containsPair('level', anything)));
      expect(document, isNot(containsPair('rank', anything)));
      expect(document, isNot(containsPair('streak', anything)));
      expect(document, isNot(containsPair('subscriptionStatus', anything)));
      expect(document, isNot(containsPair('userRole', anything)));
      expect(document, isNot(containsPair('email', anything)));
    });

    test('serializes only changed personal profile fields', () {
      final snapshot = UserProfilePersonalSnapshot(
        fullName: 'Maya Tan',
        nickname: 'May',
        dateOfBirthIso: '2000-01-01',
        ageYears: 26,
        weightKg: 59,
        locationLabel: 'Tiong Bahru, Singapore',
      );

      final document = snapshot.toFirestoreDocument(updatedAt: 2);

      expect(document, <String, Object>{
        'fullName': 'Maya Tan',
        'dateOfBirth': '2000-01-01',
        'ageYears': 26,
        'weightKg': 59,
        'locationLabel': 'Tiong Bahru, Singapore',
        'updatedAt': 2,
      });
      expect(document, isNot(containsPair('email', anything)));
      expect(document, isNot(containsPair('fitnessLevel', anything)));
    });
  });

  group('FirestoreUserProfilePersistenceRepository', () {
    test(
      'availability delegates the original nickname to the callable seam',
      () async {
        final writer = _RecordingUserProfileDocumentWriter();
        final repository = FirestoreUserProfilePersistenceRepository(
          writer: writer,
        );

        final available = await repository.isNicknameAvailable(
          uid: 'test-auth-user-1',
          nickname: 'Élodie Runner',
        );

        expect(available, isTrue);
        expect(writer.checkedNickname, 'Élodie Runner');
      },
    );

    test(
      'merges the onboarding profile under the authenticated user id',
      () async {
        final writer = _RecordingUserProfileDocumentWriter();
        final repository = FirestoreUserProfilePersistenceRepository(
          writer: writer,
          updatedAt: () => 42,
        );

        await repository.saveOnboardingProfile(
          uid: 'test-auth-user-1',
          profile: UserProfileOnboardingSnapshot(
            displayName: 'Maya',
            fullName: 'Maya Tan',
            nickname: 'Maya',
            avatarInitials: 'M',
            dateOfBirthIso: '2002-06-28',
            ageYears: 24,
            weightKg: 58.5,
            locationLabel: 'Queenstown, Singapore',
            fitnessLevel: 'new',
            goals: const <String>['habit'],
            availability: const <String, Object>{
              'weeklySessions': '3',
              'preferredDays': <String>['Mon', 'Wed', 'Fri'],
              'preferredTime': 'morning',
              'sessionLengthMinutes': '20',
            },
            planCautiousness: 'balanced',
            healthSafetyReadiness: const <String, Object>{
              'comfort': 'ready',
              'activitySymptoms': <String>['none'],
              'recentRunningConsistency': 'none',
              'currentWeeklyRunFrequency': '0',
              'continuousRunCapacity': 'walk',
              'runningPlace': 'park',
              'motivationStyle': 'reminders',
            },
          ),
        );

        expect(writer.uid, 'test-auth-user-1');
        expect(writer.calls, <String>['mergeUserProfile', 'upsertNickname']);
        expect(writer.data?['updatedAt'], 42);
        expect(writer.data?['fullName'], 'Maya Tan');
        expect(writer.nickname, 'Maya');
        expect(writer.data?['dateOfBirth'], '2002-06-28');
        expect(writer.data?['ageYears'], 24);
        expect(writer.data?['weightKg'], 58.5);
        expect(writer.data?['locationLabel'], 'Queenstown, Singapore');
        expect(writer.data, isNot(containsPair('nickname', anything)));
        expect(writer.data, isNot(containsPair('displayName', anything)));
        expect(writer.data, isNot(containsPair('nicknameKey', anything)));
        expect(writer.data?['fitnessLevel'], 'new');
        expect(
          writer.data,
          isNot(containsPair('subscriptionStatus', anything)),
        );
        expect(writer.data, isNot(containsPair('userRole', anything)));
      },
    );

    test(
      'merges personal profile updates without onboarding or email fields',
      () async {
        final writer = _RecordingUserProfileDocumentWriter();
        final repository = FirestoreUserProfilePersistenceRepository(
          writer: writer,
          updatedAt: () => 43,
        );

        await repository.savePersonalProfile(
          uid: 'test-auth-user-1',
          profile: UserProfilePersonalSnapshot(
            fullName: 'Maya Tan',
            nickname: 'May',
            dateOfBirthIso: '2000-01-01',
            ageYears: 26,
            weightKg: 59,
            locationLabel: 'Tiong Bahru, Singapore',
          ),
        );

        expect(writer.uid, 'test-auth-user-1');
        expect(writer.calls, <String>['mergeUserProfile', 'upsertNickname']);
        expect(writer.data?['updatedAt'], 43);
        expect(writer.nickname, 'May');
        expect(writer.data?['dateOfBirth'], '2000-01-01');
        expect(writer.data?['locationLabel'], 'Tiong Bahru, Singapore');
        expect(writer.data, isNot(containsPair('email', anything)));
        expect(writer.data, isNot(containsPair('fitnessLevel', anything)));
        expect(writer.data, isNot(containsPair('goals', anything)));
      },
    );

    test('does not generate a legacy ASCII nickname key', () {
      final draft = PersonalProfileDraft.tryCreate(
        fullName: 'Maya Tan',
        nickname: '  May Runner  ',
        dateOfBirthIso: '2000-01-01',
        weightKg: '59',
        locationLabel: 'Orchard, Singapore',
      );

      expect(draft, isNotNull);
      expect(draft?.ageYears, 26);
    });
  });
}

class _RecordingUserProfileDocumentWriter implements UserProfileDocumentWriter {
  String? uid;
  Map<String, Object>? data;
  String? nickname;
  String? checkedNickname;
  final calls = <String>[];

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async {
    this.uid = uid;
    calls.add('isNicknameAvailable');
    checkedNickname = nickname;
    return true;
  }

  @override
  Future<void> mergeUserProfile({
    required String uid,
    required Map<String, Object> data,
  }) async {
    this.uid = uid;
    calls.add('mergeUserProfile');
    this.data = Map<String, Object>.from(data);
  }

  @override
  Future<void> upsertNickname({
    required String uid,
    required String nickname,
  }) async {
    this.uid = uid;
    this.nickname = nickname;
    calls.add('upsertNickname');
  }
}
