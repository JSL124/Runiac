import '../../../onboarding/domain/models/local_onboarding_draft.dart';

/// Backend-produced account profile display contract.
///
/// Identity, account, region, and progression labels are read-only outputs for
/// Flutter. Future persistence must come from approved backend/Auth read paths.
class UserProfileReadModel {
  UserProfileReadModel({
    required this.userId,
    required this.displayName,
    this.fullName = '',
    this.nickname = '',
    this.dateOfBirthIso = '',
    required this.avatarInitials,
    this.avatarUrl = '',
    this.ageYears,
    this.weightKg,
    required this.locationLabel,
    this.previewLevelBadge = '',
    this.previewNote = '',
    this.setupSectionLabel = '',
    this.manageSectionLabel = '',
    this.footerCaption = '',
    this.setupNote = '',
    this.onboardingDraft,
    List<UserProfileInfoItemReadModel> setupItems =
        const <UserProfileInfoItemReadModel>[],
    List<UserProfileManageRowReadModel> manageRows =
        const <UserProfileManageRowReadModel>[],
  }) : setupItems = List.unmodifiable(setupItems),
       manageRows = List.unmodifiable(manageRows);

  final String userId;
  final String displayName;
  final String fullName;
  final String nickname;
  final String dateOfBirthIso;
  final String avatarInitials;

  /// Raw, not-yet-sanitised avatar photo URL from `userProfiles/{uid}`.
  /// Empty when no photo is set. Always passed through
  /// `resolveProfileAvatarUrl` at render time before reaching an
  /// `Image`/`NetworkImage`.
  final String avatarUrl;
  final int? ageYears;
  final num? weightKg;
  final String locationLabel;
  final String previewLevelBadge;
  final String previewNote;
  final String setupSectionLabel;
  final String manageSectionLabel;
  final String footerCaption;

  /// Plain-language reason for the training setup shown in [setupItems];
  /// empty when the stored answers could not be resolved into a draft.
  final String setupNote;
  final LocalOnboardingDraft? onboardingDraft;
  final List<UserProfileInfoItemReadModel> setupItems;
  final List<UserProfileManageRowReadModel> manageRows;
}

class UserProfileInfoItemReadModel {
  const UserProfileInfoItemReadModel({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;
}

class UserProfileManageRowReadModel {
  const UserProfileManageRowReadModel({
    required this.title,
    required this.subtitle,
    required this.snackBarMessage,
    this.action = UserProfileManageAction.snackBar,
  });

  final String title;
  final String subtitle;
  final String snackBarMessage;
  final UserProfileManageAction action;
}

enum UserProfileManageAction {
  snackBar,
  editProfile,
  runningBuddy,
  notifications,
  privacySafety,
  feedback,
  settings,
  about,
}
