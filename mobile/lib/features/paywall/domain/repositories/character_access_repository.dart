import '../models/character_access_read_model.dart';

/// Read-only access to the backend-owned `config/characterAccess` document.
/// There is deliberately no write method: `firestore.rules` denies all client
/// writes to `config/*`, and character tiers are owned by the admin console.
abstract interface class CharacterAccessRepository {
  Future<CharacterAccessReadModel> loadCharacterAccess();
}

/// Preview/test default. Reports the built-in defaults instantly.
class StaticCharacterAccessRepository implements CharacterAccessRepository {
  const StaticCharacterAccessRepository();

  @override
  Future<CharacterAccessReadModel> loadCharacterAccess() async {
    return CharacterAccessReadModel.defaults;
  }
}
