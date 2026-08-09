import '../models/local_onboarding_draft.dart';
import 'safety_gate_resolver.dart';

enum RunnerLevel { starter, developing, performance, advanced }

class RunnerLevelResolver {
  const RunnerLevelResolver([
    this._safetyGateResolver = const SafetyGateResolver(),
  ]);

  final SafetyGateResolver _safetyGateResolver;

  RunnerLevel resolve(LocalOnboardingDraft draft) {
    final safetyGate = _safetyGateResolver.resolve(draft);
    if (safetyGate == SafetyGateState.needsClearance ||
        safetyGate == SafetyGateState.restricted) {
      return RunnerLevel.starter;
    }

    if (_isStarter(draft)) {
      return RunnerLevel.starter;
    }

    if (_isAdvanced(draft)) {
      return RunnerLevel.advanced;
    }

    if (_isPerformance(draft)) {
      return RunnerLevel.performance;
    }

    if (_isDeveloping(draft)) {
      return RunnerLevel.developing;
    }

    return RunnerLevel.starter;
  }

  bool _isStarter(LocalOnboardingDraft draft) {
    return draft.recentRunningConsistency == RecentRunningConsistency.none ||
        draft.recentRunningConsistency ==
            RecentRunningConsistency.underFourWeeks ||
        draft.currentWeeklyRunFrequency == CurrentWeeklyRunFrequency.zero ||
        draft.currentWeeklyRunFrequency == CurrentWeeklyRunFrequency.oneToTwo ||
        draft.continuousRunCapacity == ContinuousRunCapacity.walkOnly ||
        draft.continuousRunCapacity == ContinuousRunCapacity.runWalk ||
        draft.continuousRunCapacity == ContinuousRunCapacity.tenMinutes;
  }

  bool _isDeveloping(LocalOnboardingDraft draft) {
    return _hasAtLeastFourWeeks(draft.recentRunningConsistency) &&
        (draft.currentWeeklyRunFrequency ==
                CurrentWeeklyRunFrequency.oneToTwo ||
            draft.currentWeeklyRunFrequency ==
                CurrentWeeklyRunFrequency.three) &&
        _hasTwentyMinuteCapacity(draft.continuousRunCapacity);
  }

  bool _isPerformance(LocalOnboardingDraft draft) {
    return (draft.recentRunningConsistency ==
                RecentRunningConsistency.threeToSixMonths ||
            draft.recentRunningConsistency ==
                RecentRunningConsistency.sixMonthsPlus) &&
        (draft.currentWeeklyRunFrequency == CurrentWeeklyRunFrequency.three ||
            draft.currentWeeklyRunFrequency == CurrentWeeklyRunFrequency.four ||
            draft.currentWeeklyRunFrequency ==
                CurrentWeeklyRunFrequency.fivePlus) &&
        (draft.continuousRunCapacity ==
                ContinuousRunCapacity.fortyFivePlusMinutes ||
            draft.continuousRunCapacity ==
                ContinuousRunCapacity.sixtyPlusMinutes);
  }

  bool _isAdvanced(LocalOnboardingDraft draft) {
    return draft.recentRunningConsistency ==
            RecentRunningConsistency.sixMonthsPlus &&
        (draft.currentWeeklyRunFrequency == CurrentWeeklyRunFrequency.four ||
            draft.currentWeeklyRunFrequency ==
                CurrentWeeklyRunFrequency.fivePlus) &&
        draft.continuousRunCapacity == ContinuousRunCapacity.sixtyPlusMinutes;
  }

  bool _hasAtLeastFourWeeks(RecentRunningConsistency consistency) {
    return switch (consistency) {
      RecentRunningConsistency.none ||
      RecentRunningConsistency.underFourWeeks => false,
      RecentRunningConsistency.oneToThreeMonths ||
      RecentRunningConsistency.threeToSixMonths ||
      RecentRunningConsistency.sixMonthsPlus => true,
    };
  }

  bool _hasTwentyMinuteCapacity(ContinuousRunCapacity capacity) {
    return switch (capacity) {
      ContinuousRunCapacity.walkOnly ||
      ContinuousRunCapacity.runWalk ||
      ContinuousRunCapacity.tenMinutes => false,
      ContinuousRunCapacity.twentyToThirtyMinutes ||
      ContinuousRunCapacity.fortyFivePlusMinutes ||
      ContinuousRunCapacity.sixtyPlusMinutes => true,
    };
  }
}
