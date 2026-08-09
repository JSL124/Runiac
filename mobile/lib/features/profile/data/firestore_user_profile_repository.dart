import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/domain/runiac_auth_service.dart';
import '../../onboarding/domain/models/local_onboarding_draft.dart';
import '../../onboarding/domain/services/training_profile_summary_builder.dart';
import '../domain/models/user_profile_read_model.dart';
import '../domain/repositories/user_profile_repository.dart';
import 'static_user_profile_repository.dart';

abstract interface class UserProfileDocumentReader {
  Future<UserProfileDocumentReadResult> readUserProfile({required String uid});
}

class UserProfileDocumentReadResult {
  const UserProfileDocumentReadResult.exists(this.data) : exists = true;

  const UserProfileDocumentReadResult.missing()
    : exists = false,
      data = const <String, Object?>{};

  final bool exists;
  final Map<String, Object?> data;
}

enum CurrentUserProfileFailureReason { missing, invalid }

class CurrentUserProfileException implements Exception {
  const CurrentUserProfileException({required this.uid, required this.reason});

  final String uid;
  final CurrentUserProfileFailureReason reason;

  @override
  String toString() {
    return 'CurrentUserProfileException(uid: $uid, reason: $reason)';
  }
}

class FirestoreUserProfileDocumentReader implements UserProfileDocumentReader {
  FirestoreUserProfileDocumentReader({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<UserProfileDocumentReadResult> readUserProfile({
    required String uid,
  }) async {
    final snapshot = await _firestore.collection('userProfiles').doc(uid).get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      return const UserProfileDocumentReadResult.missing();
    }
    return UserProfileDocumentReadResult.exists(
      Map<String, Object?>.from(data),
    );
  }
}

class FirestoreUserProfileRepository implements UserProfileRepository {
  FirestoreUserProfileRepository({
    required this.authRepository,
    UserProfileDocumentReader? reader,
    this.fallbackRepository = const StaticUserProfileRepository(),
  }) : documentReader = reader ?? FirestoreUserProfileDocumentReader();

  final RuniacAuthRepository authRepository;
  final UserProfileDocumentReader documentReader;
  final UserProfileRepository fallbackRepository;

  @override
  Future<UserProfileReadModel> loadUserProfile() async {
    final currentUser = authRepository.currentUser;
    if (currentUser == null) {
      return fallbackRepository.loadUserProfile();
    }

    final result = await documentReader.readUserProfile(uid: currentUser.uid);
    if (!result.exists) {
      throw CurrentUserProfileException(
        uid: currentUser.uid,
        reason: CurrentUserProfileFailureReason.missing,
      );
    }

    final profile = _mapDocument(currentUser.uid, result.data);
    if (profile == null) {
      throw CurrentUserProfileException(
        uid: currentUser.uid,
        reason: CurrentUserProfileFailureReason.invalid,
      );
    }
    return profile;
  }

  UserProfileReadModel? _mapDocument(
    String uid,
    Map<String, Object?> document,
  ) {
    final displayName = _requiredTrimmedString(document['displayName']);
    final fullName = _optionalTrimmedString(document['fullName']);
    final nickname = _optionalTrimmedString(document['nickname']);
    final dateOfBirthIso = _optionalTrimmedString(document['dateOfBirth']);
    final avatarInitials = _requiredTrimmedString(document['avatarInitials']);
    final avatarUrl = _optionalTrimmedString(document['avatarUrl']);
    final ageYears = _intValue(document['ageYears']);
    final weightKg = _numValue(document['weightKg']);
    final locationLabel = _requiredTrimmedString(document['locationLabel']);
    if (displayName == null ||
        avatarInitials == null ||
        locationLabel == null) {
      return null;
    }

    final onboardingDraft = _onboardingDraftFromDocument(document);
    final trainingProfile = onboardingDraft == null
        ? null
        : const TrainingProfileSummaryBuilder().build(onboardingDraft);

    return UserProfileReadModel(
      userId: uid,
      displayName: displayName,
      fullName: fullName,
      nickname: nickname,
      dateOfBirthIso: dateOfBirthIso,
      avatarInitials: avatarInitials,
      avatarUrl: avatarUrl,
      ageYears: ageYears,
      weightKg: weightKg,
      locationLabel: locationLabel,
      previewLevelBadge: '',
      previewNote: '',
      setupSectionLabel: 'YOUR TRAINING PROFILE',
      manageSectionLabel: 'MANAGE',
      footerCaption: 'Runiac · Preview build · Built for new runners',
      setupNote: trainingProfile?.note ?? '',
      onboardingDraft: onboardingDraft,
      setupItems: trainingProfile == null
          ? _legacySetupItemsFromDocument(document)
          : trainingProfile.rows
                .map(
                  (row) => UserProfileInfoItemReadModel(
                    title: row.label,
                    value: row.value,
                  ),
                )
                .toList(growable: false),
      manageRows: const <UserProfileManageRowReadModel>[
        UserProfileManageRowReadModel(
          title: 'Edit profile',
          subtitle: 'Personal details and onboarding',
          snackBarMessage: '',
          action: UserProfileManageAction.editProfile,
        ),
        // Settings is deliberately absent: it lives in the Profile header's
        // overflow menu, not in this list.
        UserProfileManageRowReadModel(
          title: 'Running buddy',
          subtitle: 'Change your guide character',
          snackBarMessage: '',
          action: UserProfileManageAction.runningBuddy,
        ),
        UserProfileManageRowReadModel(
          title: 'Privacy & Safety',
          subtitle: 'Guide data use and sharing',
          snackBarMessage: '',
          action: UserProfileManageAction.privacySafety,
        ),
        UserProfileManageRowReadModel(
          title: 'Notifications',
          subtitle: 'Gentle running nudges and reminders',
          snackBarMessage: 'Notification preferences preview is coming soon.',
          action: UserProfileManageAction.notifications,
        ),
        UserProfileManageRowReadModel(
          title: 'About Runiac',
          subtitle: 'App version and project information',
          snackBarMessage: '',
          action: UserProfileManageAction.about,
        ),
        UserProfileManageRowReadModel(
          title: 'Feedback',
          subtitle: 'Report a bug or share a suggestion',
          snackBarMessage: '',
          action: UserProfileManageAction.feedback,
        ),
      ],
    );
  }

  LocalOnboardingDraft? _onboardingDraftFromDocument(
    Map<String, Object?> document,
  ) {
    final goal = _stringList(document['goals']).firstOrNull;
    final experience = _requiredTrimmedString(document['fitnessLevel']);
    final availability = document['availability'];
    final safety = document['healthSafetyReadiness'];
    if (goal == null || availability is! Map || safety is! Map) {
      return null;
    }

    final planPreference = _requiredTrimmedString(document['planCautiousness']);
    final answers = <String, Object>{
      'goal': goal,
      'experience': experience ?? '',
      'availability':
          _requiredTrimmedString(availability['weeklySessions']) ?? '',
      'days': _stringList(availability['preferredDays']),
      'time': _requiredTrimmedString(availability['preferredTime']) ?? '',
      'length':
          _requiredTrimmedString(availability['sessionLengthMinutes']) ?? '',
      'health': _requiredTrimmedString(safety['comfort']) ?? '',
      'symptoms': _stringList(safety['activitySymptoms']),
      'consistency':
          _requiredTrimmedString(safety['recentRunningConsistency']) ?? '',
      'frequency':
          _requiredTrimmedString(safety['currentWeeklyRunFrequency']) ?? '',
      'capacity': _requiredTrimmedString(safety['continuousRunCapacity']) ?? '',
      'place': _requiredTrimmedString(safety['runningPlace']) ?? '',
      'motivation': _requiredTrimmedString(safety['motivationStyle']) ?? '',
    };

    if (OnboardingPlanStyle.fromValue(planPreference) != null) {
      answers['style'] = planPreference!;
    } else {
      answers['cautious'] = planPreference ?? '';
    }

    return LocalOnboardingDraft.fromAnswers(answers);
  }

  /// Older documents predate the enum-backed onboarding answers and store
  /// display strings that no resolver can interpret. They still get readable
  /// rows: known answer codes are mapped to their onboarding wording and
  /// anything else is relayed as stored.
  List<UserProfileInfoItemReadModel> _legacySetupItemsFromDocument(
    Map<String, Object?> document,
  ) {
    final items = <UserProfileInfoItemReadModel>[];
    final goals = _stringList(document['goals']);
    if (goals.isNotEmpty) {
      items.add(
        UserProfileInfoItemReadModel(
          title: 'Current goal',
          value: goals.map(_goalLabel).join(', '),
        ),
      );
    }

    final weeklySessions = _weeklySessionsLabel(document['availability']);
    if (weeklySessions != null) {
      items.add(
        UserProfileInfoItemReadModel(title: 'Schedule', value: weeklySessions),
      );
    }

    final fitnessLevel = _requiredTrimmedString(document['fitnessLevel']);
    if (fitnessLevel != null) {
      items.add(
        UserProfileInfoItemReadModel(
          title: 'Starting point',
          value: _experienceLabel(fitnessLevel),
        ),
      );
    }
    return items;
  }

  String _goalLabel(String storedGoal) {
    final goal = OnboardingGoal.fromValue(storedGoal);
    return goal == null ? storedGoal : onboardingGoalLabel(goal);
  }

  String _experienceLabel(String storedExperience) {
    final experience = OnboardingExperience.fromValue(storedExperience);
    return experience == null
        ? storedExperience
        : onboardingExperienceLabel(experience);
  }

  String? _weeklySessionsLabel(Object? availability) {
    if (availability is! Map) {
      return null;
    }
    final sessions = _requiredTrimmedString(availability['weeklySessions']);
    if (sessions == null) {
      return null;
    }
    // 'unsure' is a stored answer code, not a session count, so relaying it
    // verbatim would render "unsure sessions / week".
    if (OnboardingAvailability.fromValue(sessions) ==
        OnboardingAvailability.unsure) {
      final suggested = requiredPreferredDayCountForAvailability(
        OnboardingAvailability.unsure,
      );
      return '$suggested sessions / week (suggested)';
    }
    return '$sessions sessions / week';
  }

  List<String> _stringList(Object? value) {
    if (value is! Iterable) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String? _requiredTrimmedString(Object? value) {
    if (value is! String) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _optionalTrimmedString(Object? value) {
    if (value is! String) {
      return '';
    }
    return value.trim();
  }

  int? _intValue(Object? value) {
    return value is int ? value : null;
  }

  num? _numValue(Object? value) {
    return value is num ? value : null;
  }
}
