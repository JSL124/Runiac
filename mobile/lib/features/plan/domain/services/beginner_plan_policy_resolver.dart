import '../../../onboarding/domain/models/local_onboarding_draft.dart';
import '../models/beginner_plan_profile.dart';

/// Decides how often the runner trains and on which days.
///
/// The user says how many days a week they can run and which ones they prefer,
/// but those answers can be unusable on their own — three sessions crammed into
/// consecutive days is worse for a beginner than three spread out.
/// [_DaySpacingScore] is how this is resolved: candidate day sets are scored on
/// spacing and the best-spaced one that respects the stated preference wins.
///
/// The safety gate can lower the session count below what was asked for; it is
/// never raised above it.
class BeginnerPlanPolicyResolver {
  const BeginnerPlanPolicyResolver();

  BeginnerPlanPolicy resolve(LocalOnboardingDraft draft) {
    final profile = _profileFor(draft);
    final requiredSessions = _requiredSessionsFor(draft, profile);
    return BeginnerPlanPolicy(
      profile: profile,
      requiredSessions: requiredSessions,
      userCapMinutes: _userCapMinutesFor(draft),
      selectedDays: selectPreferredDays(draft.preferredDays, requiredSessions),
    );
  }

  List<OnboardingPreferredDay> selectPreferredDays(
    List<OnboardingPreferredDay> preferredDays,
    int requiredSessions,
  ) {
    final sorted = [...preferredDays]..sort(_compareDays);
    if (sorted.length <= requiredSessions) {
      return sorted;
    }

    final combinations = <List<OnboardingPreferredDay>>[];
    _collectCombinations(sorted, requiredSessions, 0, [], combinations);
    combinations.sort(_compareCombinations);
    return combinations.last;
  }

  BeginnerPlanProfile _profileFor(LocalOnboardingDraft draft) {
    final safetyBand = _safetyBandFor(draft);
    final experienceBand = _experienceBandFor(draft);
    final cautionIntent = _cautionIntentFor(draft);
    return BeginnerPlanProfile(
      safetyBand: safetyBand,
      experienceBand: experienceBand,
      cautionIntent: cautionIntent,
      templateKind: _templateKindFor(
        safetyBand: safetyBand,
        experienceBand: experienceBand,
        cautionIntent: cautionIntent,
      ),
    );
  }

  BeginnerPlanSafetyBand _safetyBandFor(LocalOnboardingDraft draft) {
    if (draft.healthComfort == OnboardingHealthComfort.heart ||
        draft.healthComfort == OnboardingHealthComfort.advised ||
        draft.activitySymptoms.any(_isSafetyFirstSymptom)) {
      return BeginnerPlanSafetyBand.safetyFirst;
    }

    if (draft.healthComfort == OnboardingHealthComfort.injury ||
        draft.healthComfort == OnboardingHealthComfort.joint ||
        draft.healthComfort == OnboardingHealthComfort.asthma ||
        draft.activitySymptoms.contains(OnboardingActivitySymptom.legpain)) {
      return BeginnerPlanSafetyBand.highCaution;
    }

    if (draft.healthComfort == OnboardingHealthComfort.breakAfterTimeAway ||
        draft.healthComfort == OnboardingHealthComfort.unsure ||
        draft.planStyle == OnboardingPlanStyle.auto ||
        draft.activitySymptoms.isEmpty) {
      return BeginnerPlanSafetyBand.cautious;
    }

    return BeginnerPlanSafetyBand.clear;
  }

  bool _isSafetyFirstSymptom(OnboardingActivitySymptom symptom) {
    return switch (symptom) {
      OnboardingActivitySymptom.chest ||
      OnboardingActivitySymptom.dizzy ||
      OnboardingActivitySymptom.breath ||
      OnboardingActivitySymptom.heartbeat => true,
      OnboardingActivitySymptom.legpain ||
      OnboardingActivitySymptom.none => false,
    };
  }

  BeginnerPlanExperienceBand _experienceBandFor(LocalOnboardingDraft draft) {
    return switch (draft.experience) {
      OnboardingExperience.newRunner => BeginnerPlanExperienceBand.newStarter,
      OnboardingExperience.walk => BeginnerPlanExperienceBand.walkBase,
      OnboardingExperience.intervals => BeginnerPlanExperienceBand.runWalkBase,
      OnboardingExperience.run10 => BeginnerPlanExperienceBand.shortRunBase,
      OnboardingExperience.run30 => BeginnerPlanExperienceBand.returningBase,
    };
  }

  BeginnerPlanCautionIntent _cautionIntentFor(LocalOnboardingDraft draft) {
    return switch (draft.planStyle) {
      OnboardingPlanStyle.conservativeBase =>
        BeginnerPlanCautionIntent.veryGentle,
      OnboardingPlanStyle.balanced => BeginnerPlanCautionIntent.balanced,
      OnboardingPlanStyle.performanceFocused =>
        BeginnerPlanCautionIntent.standard,
      OnboardingPlanStyle.auto => BeginnerPlanCautionIntent.conservative,
    };
  }

  BeginnerPlanTemplateKind _templateKindFor({
    required BeginnerPlanSafetyBand safetyBand,
    required BeginnerPlanExperienceBand experienceBand,
    required BeginnerPlanCautionIntent cautionIntent,
  }) {
    if (safetyBand == BeginnerPlanSafetyBand.safetyFirst) {
      return BeginnerPlanTemplateKind.safetyFirstMovementStart;
    }

    if (safetyBand == BeginnerPlanSafetyBand.highCaution ||
        cautionIntent == BeginnerPlanCautionIntent.veryGentle ||
        experienceBand == BeginnerPlanExperienceBand.newStarter ||
        experienceBand == BeginnerPlanExperienceBand.walkBase) {
      return BeginnerPlanTemplateKind.veryGentleStart;
    }

    if (experienceBand == BeginnerPlanExperienceBand.returningBase &&
        (cautionIntent == BeginnerPlanCautionIntent.standard ||
            cautionIntent == BeginnerPlanCautionIntent.balanced)) {
      return BeginnerPlanTemplateKind.returningBeginnerStart;
    }

    return BeginnerPlanTemplateKind.standardBeginnerStart;
  }

  int _requiredSessionsFor(
    LocalOnboardingDraft draft,
    BeginnerPlanProfile profile,
  ) {
    final base = draft.requestedWeeklySessionCount;
    if (profile.templateKind ==
        BeginnerPlanTemplateKind.safetyFirstMovementStart) {
      return _min(base, 2);
    }
    if (profile.safetyBand == BeginnerPlanSafetyBand.highCaution ||
        profile.cautionIntent == BeginnerPlanCautionIntent.veryGentle) {
      return _min(base, 3);
    }
    return base;
  }

  int _userCapMinutesFor(LocalOnboardingDraft draft) {
    return switch (draft.sessionLength) {
      OnboardingSessionLength.fifteen => 15,
      OnboardingSessionLength.twenty => 20,
      OnboardingSessionLength.thirty => 30,
      OnboardingSessionLength.fortyFive => 45,
      OnboardingSessionLength.unsure => 20,
    };
  }

  void _collectCombinations(
    List<OnboardingPreferredDay> source,
    int size,
    int start,
    List<OnboardingPreferredDay> current,
    List<List<OnboardingPreferredDay>> result,
  ) {
    if (current.length == size) {
      result.add(List.unmodifiable(current));
      return;
    }

    for (var index = start; index < source.length; index++) {
      current.add(source[index]);
      _collectCombinations(source, size, index + 1, current, result);
      current.removeLast();
    }
  }

  int _compareCombinations(
    List<OnboardingPreferredDay> left,
    List<OnboardingPreferredDay> right,
  ) {
    final leftScore = _DaySpacingScore.fromDays(left);
    final rightScore = _DaySpacingScore.fromDays(right);
    final minGap = leftScore.minGap.compareTo(rightScore.minGap);
    if (minGap != 0) {
      return minGap;
    }

    final imbalance = rightScore.imbalance.compareTo(leftScore.imbalance);
    if (imbalance != 0) {
      return imbalance;
    }

    for (var index = 0; index < left.length; index++) {
      final weekday = _dayIndex(right[index]).compareTo(_dayIndex(left[index]));
      if (weekday != 0) {
        return weekday;
      }
    }

    return 0;
  }
}

class _DaySpacingScore {
  const _DaySpacingScore({required this.minGap, required this.imbalance});

  factory _DaySpacingScore.fromDays(List<OnboardingPreferredDay> days) {
    final indexes = days.map(_dayIndex).toList(growable: false)..sort();
    final gaps = <int>[];
    for (var index = 0; index < indexes.length; index++) {
      final current = indexes[index];
      final next = indexes[(index + 1) % indexes.length];
      gaps.add((next - current + 7) % 7);
    }
    gaps.sort();
    return _DaySpacingScore(
      minGap: gaps.first,
      imbalance: gaps.last - gaps.first,
    );
  }

  final int minGap;
  final int imbalance;
}

int _compareDays(OnboardingPreferredDay left, OnboardingPreferredDay right) {
  return _dayIndex(left).compareTo(_dayIndex(right));
}

int _dayIndex(OnboardingPreferredDay day) {
  return OnboardingPreferredDay.values.indexOf(day);
}

int _min(int left, int right) {
  return left < right ? left : right;
}
