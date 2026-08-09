import '../models/user_profile_read_model.dart';

abstract interface class UserProfileRepository {
  Future<UserProfileReadModel> loadUserProfile();
}
