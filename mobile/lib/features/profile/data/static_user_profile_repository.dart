import '../domain/models/user_profile_read_model.dart';
import '../domain/repositories/user_profile_repository.dart';
import '../presentation/data/account_profile_demo_snapshots.dart';

class StaticUserProfileRepository implements UserProfileRepository {
  const StaticUserProfileRepository();

  @override
  Future<UserProfileReadModel> loadUserProfile() async {
    const snapshot = accountProfileDemoSnapshot;

    return UserProfileReadModel(
      userId: 'demo-user',
      displayName: snapshot.displayName,
      fullName: 'Runiac Runner',
      nickname: snapshot.displayName,
      dateOfBirthIso: '2000-01-01',
      avatarInitials: snapshot.avatarInitials,
      ageYears: 26,
      weightKg: 60,
      locationLabel: snapshot.regionLabel,
      previewLevelBadge: snapshot.previewLevelBadge,
      previewNote: snapshot.previewNote,
      setupSectionLabel: snapshot.setupSectionLabel,
      manageSectionLabel: snapshot.manageSectionLabel,
      footerCaption: snapshot.footerCaption,
      setupNote: snapshot.setupNote,
      setupItems: snapshot.setupItems
          .map(
            (item) => UserProfileInfoItemReadModel(
              title: item.title,
              value: item.value,
            ),
          )
          .toList(growable: false),
      manageRows: snapshot.manageRows
          .map(
            (row) => UserProfileManageRowReadModel(
              title: row.title,
              subtitle: row.subtitle,
              snackBarMessage: row.snackBarMessage,
              action: row.action,
            ),
          )
          .toList(growable: false),
    );
  }
}
