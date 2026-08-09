import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/domain/runiac_auth_service.dart';
import '../domain/models/user_account_read_model.dart';
import '../domain/repositories/user_account_repository.dart';

abstract interface class UserAccountDocumentReader {
  Future<Map<String, Object?>?> readUserAccount({required String uid});
}

abstract interface class LiveUserAccountDocumentReader
    implements UserAccountDocumentReader {
  Stream<Map<String, Object?>?> watchUserAccount({required String uid});
}

/// Reads the owner-readable top-level `users/{uid}` document.
///
/// `firestore.rules` grants `allow read: if isOwner(uid)` and denies every
/// client create/update/delete on this document, so this reader is read-only
/// by construction.
class FirestoreUserAccountDocumentReader
    implements LiveUserAccountDocumentReader {
  FirestoreUserAccountDocumentReader({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<Map<String, Object?>?> readUserAccount({required String uid}) async {
    final snapshot = await _firestore.collection('users').doc(uid).get();
    final data = snapshot.data();
    return data == null ? null : Map<String, Object?>.from(data);
  }

  @override
  Stream<Map<String, Object?>?> watchUserAccount({required String uid}) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      return data == null ? null : Map<String, Object?>.from(data);
    });
  }
}

class FirestoreUserAccountRepository
    implements UserAccountRepository, LiveUserAccountRepository {
  FirestoreUserAccountRepository({
    required this.authRepository,
    UserAccountDocumentReader? reader,
  }) : _reader = reader ?? FirestoreUserAccountDocumentReader();

  final RuniacAuthRepository authRepository;
  final UserAccountDocumentReader _reader;

  @override
  Future<UserAccountReadModel> loadUserAccount() async {
    final uid = authRepository.currentUser?.uid;
    if (uid == null) {
      return const UserAccountReadModel();
    }
    return _mapDocument(await _reader.readUserAccount(uid: uid));
  }

  @override
  Stream<UserAccountReadModel> watchUserAccount() {
    final uid = authRepository.currentUser?.uid;
    final reader = _reader;
    if (uid == null || reader is! LiveUserAccountDocumentReader) {
      return Stream.fromFuture(loadUserAccount());
    }
    return reader.watchUserAccount(uid: uid).map(_mapDocument);
  }

  UserAccountReadModel _mapDocument(Map<String, Object?>? data) {
    return UserAccountReadModel(
      subscriptionStatus: _subscriptionStatus(data?['subscriptionStatus']),
    );
  }

  /// Coerces the trusted raw field. A missing document, a missing field, or an
  /// unrecognised value resolves to Basic so an unknown value is never shown
  /// as Premium.
  UserSubscriptionStatus _subscriptionStatus(Object? value) {
    if (value is! String) {
      return UserSubscriptionStatus.basic;
    }
    return value.trim().toLowerCase() == 'premium'
        ? UserSubscriptionStatus.premium
        : UserSubscriptionStatus.basic;
  }
}
