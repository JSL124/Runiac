import '../singapore_region_options.dart';

/// The contract for reading and writing the runner's own profile.
///
/// Nickname availability is the interesting part. It has three outcomes, not
/// two: available, taken, and *could not be checked* —
/// [NicknameAvailabilityFailureReason.rulesUnavailable] is what a permission
/// failure looks like. They are distinguished because treating "we could not
/// check" as "taken" would block a legitimate nickname, and treating it as
/// "available" would let the save fail later with no explanation.
abstract interface class UserProfilePersistenceRepository {
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  });

  Future<void> saveOnboardingProfile({
    required String uid,
    required UserProfileOnboardingSnapshot profile,
  });

  Future<void> savePersonalProfile({
    required String uid,
    required UserProfilePersonalSnapshot profile,
  });
}

class NicknameAvailabilityCheckException implements Exception {
  const NicknameAvailabilityCheckException(this.reason);

  final NicknameAvailabilityFailureReason reason;
}

class NicknameUnavailableException implements Exception {
  const NicknameUnavailableException();
}

enum NicknameAvailabilityFailureReason { rulesUnavailable, unavailable }

class PersonalProfileDraft {
  PersonalProfileDraft({
    required String fullName,
    required String nickname,
    required String dateOfBirthIso,
    required this.weightKg,
    required String locationLabel,
  }) : fullName = fullName.trim(),
       nickname = nickname.trim(),
       dateOfBirthIso = dateOfBirthIso.trim(),
       locationLabel = locationLabel.trim();

  final String fullName;
  final String nickname;
  final String dateOfBirthIso;
  final num weightKg;
  final String locationLabel;

  String get displayName => nickname;

  String get avatarInitials => _avatarInitials(nickname, fullName);

  int get ageYears => ageFromBirthDateIso(dateOfBirthIso);

  UserProfilePersonalSnapshot toPersonalSnapshot() {
    return UserProfilePersonalSnapshot(
      fullName: fullName,
      nickname: nickname,
      dateOfBirthIso: dateOfBirthIso,
      ageYears: ageYears,
      weightKg: weightKg,
      locationLabel: locationLabel,
    );
  }

  static String? validateFullName(String value) {
    return _validateText(value, 'Name', 80);
  }

  static String? validateNickname(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.runes.length > 30) {
      return 'Nickname must be 1-30 characters.';
    }
    if (RegExp(r'[\x00-\x1F\x7F-\x9F]').hasMatch(trimmed)) {
      return 'Nickname cannot include line breaks.';
    }
    return null;
  }

  static String? validateLocationLabel(String value) {
    final textError = _validateText(value, 'Region', 80);
    if (textError != null) {
      return textError;
    }
    if (!SingaporeRegionOptions.contains(value)) {
      return 'Choose a Singapore region from the list.';
    }
    return null;
  }

  static String? validateDateOfBirth(String value) {
    final parsed = _parseBirthDate(value);
    if (parsed == null) {
      return 'Choose your birthdate.';
    }
    final age = ageFromBirthDate(parsed);
    if (age < 13 || age > 100) {
      return 'Age must be from 13 to 100.';
    }
    return null;
  }

  static String? validateWeight(String value) {
    final trimmed = value.trim();
    final parsed = num.tryParse(trimmed);
    final oneDecimal = RegExp(r'^\d+(\.\d)?$').hasMatch(trimmed);
    if (parsed == null || !oneDecimal || parsed < 30 || parsed > 250) {
      return 'Enter a weight from 30 to 250 kg.';
    }
    return null;
  }

  static PersonalProfileDraft? tryCreate({
    required String fullName,
    required String nickname,
    required String dateOfBirthIso,
    required String weightKg,
    required String locationLabel,
  }) {
    if (validateFullName(fullName) != null ||
        validateNickname(nickname) != null ||
        validateDateOfBirth(dateOfBirthIso) != null ||
        validateWeight(weightKg) != null ||
        validateLocationLabel(locationLabel) != null) {
      return null;
    }
    return PersonalProfileDraft(
      fullName: fullName,
      nickname: nickname,
      dateOfBirthIso: dateOfBirthIso,
      weightKg: num.parse(weightKg.trim()),
      locationLabel: locationLabel,
    );
  }

  static String? _validateText(String value, String label, int maxLength) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed.length > maxLength) {
      return '$label must be 1-$maxLength characters.';
    }
    if (RegExp(r'[\x00-\x1F]').hasMatch(trimmed)) {
      return '$label cannot include line breaks.';
    }
    return null;
  }
}

class UserProfilePersonalSnapshot {
  UserProfilePersonalSnapshot({
    required this.fullName,
    required this.nickname,
    required this.dateOfBirthIso,
    required this.ageYears,
    required this.weightKg,
    required this.locationLabel,
  });

  final String fullName;
  final String nickname;
  final String dateOfBirthIso;
  final int ageYears;
  final num weightKg;
  final String locationLabel;

  String get displayName => nickname;

  String get avatarInitials => _avatarInitials(nickname, fullName);

  Map<String, Object> toFirestoreDocument({required Object updatedAt}) {
    return <String, Object>{
      'fullName': fullName,
      'dateOfBirth': dateOfBirthIso,
      'ageYears': ageYears,
      'weightKg': weightKg,
      'locationLabel': locationLabel,
      'updatedAt': updatedAt,
    };
  }
}

class UserProfileOnboardingSnapshot {
  UserProfileOnboardingSnapshot({
    required this.displayName,
    required this.fullName,
    required this.nickname,
    required this.avatarInitials,
    required this.dateOfBirthIso,
    required this.ageYears,
    required this.weightKg,
    required this.locationLabel,
    required this.fitnessLevel,
    required List<String> goals,
    required Map<String, Object> availability,
    required this.planCautiousness,
    required Map<String, Object> healthSafetyReadiness,
  }) : goals = List.unmodifiable(goals),
       availability = Map.unmodifiable(availability),
       healthSafetyReadiness = Map.unmodifiable(healthSafetyReadiness);

  final String displayName;
  final String fullName;
  final String nickname;
  final String avatarInitials;
  final String dateOfBirthIso;
  final int ageYears;
  final num weightKg;
  final String locationLabel;
  final String fitnessLevel;
  final List<String> goals;
  final Map<String, Object> availability;
  final String planCautiousness;
  final Map<String, Object> healthSafetyReadiness;

  Map<String, Object> toFirestoreDocument({required Object updatedAt}) {
    return <String, Object>{
      'fullName': fullName,
      'dateOfBirth': dateOfBirthIso,
      'ageYears': ageYears,
      'weightKg': weightKg,
      'locationLabel': locationLabel,
      'fitnessLevel': fitnessLevel,
      'goals': goals,
      'availability': availability,
      'planCautiousness': planCautiousness,
      'healthSafetyReadiness': healthSafetyReadiness,
      'updatedAt': updatedAt,
    };
  }
}

class NoopUserProfilePersistenceRepository
    implements UserProfilePersistenceRepository {
  const NoopUserProfilePersistenceRepository();

  @override
  Future<bool> isNicknameAvailable({
    required String uid,
    required String nickname,
  }) async {
    return true;
  }

  @override
  Future<void> saveOnboardingProfile({
    required String uid,
    required UserProfileOnboardingSnapshot profile,
  }) async {}

  @override
  Future<void> savePersonalProfile({
    required String uid,
    required UserProfilePersonalSnapshot profile,
  }) async {}
}

String _avatarInitials(String nickname, String fullName) {
  final source = nickname.trim().isNotEmpty ? nickname.trim() : fullName.trim();
  final words = source
      .split(RegExp(r'\s+'))
      .where((word) => word.trim().isNotEmpty)
      .toList(growable: false);
  final initials = words.isNotEmpty
      ? words.map(_firstCharacter).take(3).join()
      : _firstCharacter(source);
  return initials.toUpperCase();
}

String _firstCharacter(String value) {
  if (value.runes.isEmpty) {
    return '';
  }
  return String.fromCharCode(value.runes.first);
}

int ageFromBirthDateIso(String value, {DateTime? today}) {
  final birthDate = _parseBirthDate(value);
  if (birthDate == null) {
    return 0;
  }
  return ageFromBirthDate(birthDate, today: today);
}

int ageFromBirthDate(DateTime birthDate, {DateTime? today}) {
  final now = today ?? DateTime.now();
  var age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    age -= 1;
  }
  return age;
}

String birthDateIso(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

DateTime? _parseBirthDate(String value) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  if (parsed.isAfter(DateTime.now())) {
    return null;
  }
  return parsed;
}
