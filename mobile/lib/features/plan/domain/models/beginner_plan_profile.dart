import '../../../onboarding/domain/models/local_onboarding_draft.dart';

enum BeginnerPlanSafetyBand { clear, cautious, highCaution, safetyFirst }

enum BeginnerPlanExperienceBand {
  newStarter,
  walkBase,
  runWalkBase,
  shortRunBase,
  returningBase,
}

enum BeginnerPlanCautionIntent { veryGentle, balanced, standard, conservative }

enum BeginnerPlanTemplateKind {
  safetyFirstMovementStart,
  veryGentleStart,
  standardBeginnerStart,
  returningBeginnerStart,
}

class BeginnerPlanProfile {
  const BeginnerPlanProfile({
    required this.safetyBand,
    required this.experienceBand,
    required this.cautionIntent,
    required this.templateKind,
  });

  final BeginnerPlanSafetyBand safetyBand;
  final BeginnerPlanExperienceBand experienceBand;
  final BeginnerPlanCautionIntent cautionIntent;
  final BeginnerPlanTemplateKind templateKind;
}

class BeginnerPlanPolicy {
  BeginnerPlanPolicy({
    required this.profile,
    required this.requiredSessions,
    required this.userCapMinutes,
    required List<OnboardingPreferredDay> selectedDays,
  }) : selectedDays = List.unmodifiable(selectedDays);

  static const defaultDurationWeeks = 4;
  static const hardCapMinutes = 35;

  final BeginnerPlanProfile profile;
  final int requiredSessions;
  final int userCapMinutes;
  final List<OnboardingPreferredDay> selectedDays;

  int get durationWeeks => defaultDurationWeeks;

  int get weekOneBaseMinutes {
    return switch (profile.templateKind) {
      BeginnerPlanTemplateKind.safetyFirstMovementStart => _capped(15),
      BeginnerPlanTemplateKind.veryGentleStart =>
        profile.cautionIntent == BeginnerPlanCautionIntent.veryGentle
            ? _capped(15)
            : _capped(20),
      BeginnerPlanTemplateKind.standardBeginnerStart => _capped(20),
      BeginnerPlanTemplateKind.returningBeginnerStart => _capped(25),
    };
  }

  int durationFor({required int weekNumber, required bool isLastSession}) {
    final base = weekOneBaseMinutes;
    return switch (profile.templateKind) {
      BeginnerPlanTemplateKind.safetyFirstMovementStart =>
        weekNumber <= 2 ? base : _capped(base + 5, templateCap: 20),
      BeginnerPlanTemplateKind.veryGentleStart =>
        weekNumber <= 2 ? base : _capped(base + 5, templateCap: 25),
      BeginnerPlanTemplateKind.standardBeginnerStart => _standardDuration(
        weekNumber,
        base,
        isLastSession,
      ),
      BeginnerPlanTemplateKind.returningBeginnerStart => _returningDuration(
        weekNumber,
        base,
        isLastSession,
      ),
    };
  }

  int _standardDuration(int weekNumber, int base, bool isLastSession) {
    return switch (weekNumber) {
      1 => isLastSession ? _capped(base + 5, templateCap: 25) : base,
      2 => _capped(base + 5, templateCap: 25),
      3 => _capped(base + 5, templateCap: 30),
      _ => _capped(base + 10, templateCap: 30),
    };
  }

  int _returningDuration(int weekNumber, int base, bool isLastSession) {
    return switch (weekNumber) {
      1 => isLastSession ? _capped(base + 5, templateCap: 30) : base,
      2 => _capped(base + 5, templateCap: 30),
      3 => _capped(base + 5, templateCap: hardCapMinutes),
      _ => _capped(base + 10, templateCap: hardCapMinutes),
    };
  }

  int _capped(int minutes, {int templateCap = hardCapMinutes}) {
    final cap = userCapMinutes < templateCap ? userCapMinutes : templateCap;
    final hardCap = cap < hardCapMinutes ? cap : hardCapMinutes;
    return minutes > hardCap ? hardCap : minutes;
  }
}
