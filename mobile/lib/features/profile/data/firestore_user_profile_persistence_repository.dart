import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../domain/repositories/user_profile_persistence_repository.dart';

typedef UserProfileUpdatedAtFactory = Object Function();
typedef UserProfileCallable =
    Future<Object?> Function(String name, Map<String, Object?> payload);

abstract interface class UserProfileDocumentWriter {
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  });

  Future<void> mergeUserProfile({
    required String uid,
    required Map<String, Object> data,
  });

  Future<void> upsertNickname({required String uid, required String nickname});
}

class FirestoreUserProfileDocumentWriter implements UserProfileDocumentWriter {
  FirestoreUserProfileDocumentWriter({
    this.firestore,
    FirebaseFunctions? functions,
    UserProfileCallable? callable,
  }) : _callable =
           callable ??
           _firebaseCallable(
             functions ??
                 FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
           );

  final FirebaseFirestore? firestore;
  final UserProfileCallable _callable;

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async {
    try {
      final data = await _callable(
        'checkNicknameAvailability',
        <String, Object?>{'nickname': nickname},
      );
      if (data is! Map<Object?, Object?> || data['available'] is! bool) {
        throw const NicknameAvailabilityCheckException(
          NicknameAvailabilityFailureReason.unavailable,
        );
      }
      return data['available'] as bool;
    } on NicknameAvailabilityCheckException {
      rethrow;
    } on FirebaseFunctionsException {
      throw const NicknameAvailabilityCheckException(
        NicknameAvailabilityFailureReason.unavailable,
      );
    }
  }

  @override
  Future<void> mergeUserProfile({
    required String uid,
    required Map<String, Object> data,
  }) {
    final profileRef = (firestore ?? FirebaseFirestore.instance)
        .collection('userProfiles')
        .doc(uid);
    final nonNicknameData = Map<String, Object>.fromEntries(
      data.entries.where(
        (entry) => !_nicknameOwnedByCallable.contains(entry.key),
      ),
    );
    return profileRef.set(nonNicknameData, SetOptions(merge: true));
  }

  @override
  Future<void> upsertNickname({
    required String uid,
    required String nickname,
  }) async {
    try {
      await _callable('upsertNickname', <String, Object?>{
        'nickname': nickname,
      });
    } on FirebaseFunctionsException catch (error) {
      final reason = error.details is Map<Object?, Object?>
          ? (error.details as Map<Object?, Object?>)['reason']
          : null;
      if (reason == 'NICKNAME_UNAVAILABLE') {
        throw const NicknameUnavailableException();
      }
      rethrow;
    }
  }

  static UserProfileCallable _firebaseCallable(FirebaseFunctions functions) {
    return (name, payload) async {
      final result = await functions.httpsCallable(name).call(payload);
      return result.data;
    };
  }
}

class FirestoreUserProfilePersistenceRepository
    implements UserProfilePersistenceRepository {
  FirestoreUserProfilePersistenceRepository({
    UserProfileDocumentWriter? writer,
    UserProfileUpdatedAtFactory? updatedAt,
  }) : _writer = writer ?? FirestoreUserProfileDocumentWriter(),
       _updatedAt = updatedAt ?? FieldValue.serverTimestamp;

  final UserProfileDocumentWriter _writer;
  final UserProfileUpdatedAtFactory _updatedAt;

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) {
    return _writer.isNicknameAvailable(uid: uid, nickname: nickname);
  }

  @override
  Future<void> saveOnboardingProfile({
    required String uid,
    required UserProfileOnboardingSnapshot profile,
  }) {
    return _saveProfileAndNickname(
      uid: uid,
      data: profile.toFirestoreDocument(updatedAt: _updatedAt()),
      nickname: profile.nickname,
    );
  }

  @override
  Future<void> savePersonalProfile({
    required String uid,
    required UserProfilePersonalSnapshot profile,
  }) {
    return _saveProfileAndNickname(
      uid: uid,
      data: profile.toFirestoreDocument(updatedAt: _updatedAt()),
      nickname: profile.nickname,
    );
  }

  Future<void> _saveProfileAndNickname({
    required String uid,
    required Map<String, Object> data,
    required String nickname,
  }) async {
    await _writer.mergeUserProfile(uid: uid, data: data);
    await _writer.upsertNickname(uid: uid, nickname: nickname);
  }
}

const Set<String> _nicknameOwnedByCallable = <String>{
  'displayName',
  'nickname',
  'avatarInitials',
  'nicknameKey',
  'nicknameCanonical',
  'nicknameIndexKey',
  'socialDiscoveryStatus',
  'socialListSortKey',
};
