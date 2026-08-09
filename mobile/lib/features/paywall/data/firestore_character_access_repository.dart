import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/character_access_read_model.dart';
import '../domain/repositories/character_access_repository.dart';

/// Reads the signed-in-readable `config/characterAccess` document.
///
/// `firestore.rules` grants `allow read: if isSignedIn()` for this doc and
/// denies every client write, so this reader is read-only by construction.
/// A missing document, a malformed field, or a read failure all resolve to
/// [CharacterAccessReadModel.defaults] so the picker never blocks on the
/// network.
class FirestoreCharacterAccessRepository implements CharacterAccessRepository {
  FirestoreCharacterAccessRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<CharacterAccessReadModel> loadCharacterAccess() async {
    final snapshot = await _firestore
        .collection('config')
        .doc('characterAccess')
        .get();
    final data = snapshot.data();
    return CharacterAccessReadModel.fromMap(
      data == null ? null : Map<String, Object?>.from(data),
    );
  }
}
