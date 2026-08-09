import 'package:flutter/widgets.dart';

import '../domain/models/beginner_adaptive_plan_snapshot.dart';

class CurrentSessionGeneratedPlanStore extends ChangeNotifier {
  BeginnerAdaptivePlanSnapshot? _activePlan;

  BeginnerAdaptivePlanSnapshot? get activePlan => _activePlan;

  bool get hasActivePlan => _activePlan != null;

  int get currentWeekRunningSessionCount {
    final plan = _activePlan;
    if (plan == null || !isEligibleCurrentSessionGeneratedPlan(plan)) {
      return 0;
    }

    return plan.weeks.first.workouts.where(isGeneratedPlanSession).length;
  }

  bool setActivePlan(BeginnerAdaptivePlanSnapshot snapshot) {
    if (!isDisplayableCurrentSessionGeneratedPlan(snapshot)) {
      return false;
    }

    if (identical(_activePlan, snapshot)) {
      return true;
    }

    _activePlan = snapshot;
    notifyListeners();
    return true;
  }

  void clear() {
    if (_activePlan == null) {
      return;
    }

    _activePlan = null;
    notifyListeners();
  }
}

bool isDisplayableCurrentSessionGeneratedPlan(
  BeginnerAdaptivePlanSnapshot snapshot,
) {
  return isEligibleCurrentSessionGeneratedPlan(snapshot) ||
      (snapshot.isSafetyReadinessDisplay && snapshot.weeks.isEmpty);
}

bool isEligibleCurrentSessionGeneratedPlan(
  BeginnerAdaptivePlanSnapshot snapshot,
) {
  if (!snapshot.canStartPlannedRun ||
      snapshot.isBlocked ||
      snapshot.weeks.isEmpty) {
    return false;
  }

  return snapshot.weeks.first.workouts.any(isGeneratedPlanSession);
}

bool isGeneratedPlanSession(BeginnerAdaptiveWorkout workout) {
  return switch (workout.kind) {
    BeginnerWorkoutKind.easyRun ||
    BeginnerWorkoutKind.runWalk ||
    BeginnerWorkoutKind.walkRun ||
    BeginnerWorkoutKind.recoveryWalk ||
    BeginnerWorkoutKind.steadyRun ||
    BeginnerWorkoutKind.controlledSteadyRun ||
    BeginnerWorkoutKind.longerEasyRun ||
    BeginnerWorkoutKind.recoveryRun => true,
    BeginnerWorkoutKind.restOrMobility => false,
  };
}

class CurrentSessionGeneratedPlanScope
    extends InheritedNotifier<CurrentSessionGeneratedPlanStore> {
  const CurrentSessionGeneratedPlanScope({
    required CurrentSessionGeneratedPlanStore store,
    required super.child,
    super.key,
  }) : super(notifier: store);

  static CurrentSessionGeneratedPlanStore? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<CurrentSessionGeneratedPlanScope>()
        ?.notifier;
  }

  static CurrentSessionGeneratedPlanStore of(BuildContext context) {
    final store = maybeOf(context);
    assert(store != null, 'No CurrentSessionGeneratedPlanScope found.');
    return store!;
  }
}
