import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';
import 'package:runiac_app/features/onboarding/domain/services/training_profile_summary_builder.dart';

void main() {
  group('TrainingProfileSummaryBuilder', () {
    test('renders sentences instead of stored answer codes', () {
      final summary = const TrainingProfileSummaryBuilder().build(
        _draft(
          goal: OnboardingGoal.stamina,
          experience: OnboardingExperience.run30,
        ),
      );

      expect(
        _valueFor(summary, TrainingProfileRowKind.goal),
        'Improve my stamina',
      );
      // The reported defect: raw enum codes reaching the profile card.
      for (final row in summary.rows) {
        expect(row.value, isNot(anyOf('stamina', 'run30', 'unsure', '4')));
      }
      expect(summary.note, isNotEmpty);
    });

    test('reports a resolved starting point and plan style', () {
      final summary = const TrainingProfileSummaryBuilder().build(
        _draft(
          recentRunningConsistency: RecentRunningConsistency.sixMonthsPlus,
          currentWeeklyRunFrequency: CurrentWeeklyRunFrequency.four,
          continuousRunCapacity: ContinuousRunCapacity.sixtyPlusMinutes,
          planStyle: OnboardingPlanStyle.performanceFocused,
        ),
      );

      expect(
        _valueFor(summary, TrainingProfileRowKind.startingPoint),
        'Advanced structured training',
      );
      expect(
        _valueFor(summary, TrainingProfileRowKind.planStyle),
        'Build steadily',
      );
      expect(
        _valueFor(summary, TrainingProfileRowKind.safety),
        'Cleared to start',
      );
    });

    test('marks an unsure availability and session length as suggested', () {
      final summary = const TrainingProfileSummaryBuilder().build(
        _draft(
          availability: OnboardingAvailability.unsure,
          sessionLength: OnboardingSessionLength.unsure,
          preferredDays: const <OnboardingPreferredDay>[],
        ),
      );

      expect(
        _valueFor(summary, TrainingProfileRowKind.schedule),
        '2 sessions / week (suggested) · Flexible days',
      );
      expect(
        _valueFor(summary, TrainingProfileRowKind.sessionLength),
        '15 min (suggested)',
      );
    });

    test('orders preferred days from Monday regardless of selection order', () {
      final summary = const TrainingProfileSummaryBuilder().build(
        _draft(
          availability: OnboardingAvailability.three,
          preferredDays: const <OnboardingPreferredDay>[
            OnboardingPreferredDay.sat,
            OnboardingPreferredDay.mon,
            OnboardingPreferredDay.wed,
          ],
        ),
      );

      expect(
        _valueFor(summary, TrainingProfileRowKind.schedule),
        '3 sessions / week · Mon · Wed · Sat',
      );
    });

    test('pauses schedule rows when the plan needs medical clearance', () {
      final summary = const TrainingProfileSummaryBuilder().build(
        _draft(healthComfort: OnboardingHealthComfort.heart),
      );

      expect(
        _valueFor(summary, TrainingProfileRowKind.planStyle),
        'Paused for safety',
      );
      expect(
        _valueFor(summary, TrainingProfileRowKind.schedule),
        'No workouts scheduled',
      );
      expect(
        _valueFor(summary, TrainingProfileRowKind.sessionLength),
        'Not set while paused',
      );
      expect(
        _valueFor(summary, TrainingProfileRowKind.safety),
        'Professional clearance needed',
      );
    });

    test('keeps the reported health condition out of the card', () {
      final summary = const TrainingProfileSummaryBuilder().build(
        _draft(
          healthComfort: OnboardingHealthComfort.joint,
          activitySymptoms: const <OnboardingActivitySymptom>[
            OnboardingActivitySymptom.legpain,
          ],
        ),
      );

      final rendered = [
        ...summary.rows.map((row) => row.value),
        summary.note,
      ].join(' ').toLowerCase();
      for (final leak in <String>[
        'joint',
        'knee',
        'leg pain',
        'heart',
        'asthma',
        'injury',
      ]) {
        expect(rendered, isNot(contains(leak)));
      }
      expect(
        _valueFor(summary, TrainingProfileRowKind.safety),
        'Extra care advised',
      );
    });
  });
}

String _valueFor(TrainingProfileSummary summary, TrainingProfileRowKind kind) {
  return summary.rows.firstWhere((row) => row.kind == kind).value;
}

LocalOnboardingDraft _draft({
  OnboardingGoal goal = OnboardingGoal.habit,
  OnboardingExperience experience = OnboardingExperience.intervals,
  OnboardingAvailability availability = OnboardingAvailability.four,
  List<OnboardingPreferredDay> preferredDays = const <OnboardingPreferredDay>[
    OnboardingPreferredDay.mon,
    OnboardingPreferredDay.wed,
    OnboardingPreferredDay.fri,
    OnboardingPreferredDay.sun,
  ],
  OnboardingSessionLength sessionLength = OnboardingSessionLength.thirty,
  OnboardingHealthComfort healthComfort = OnboardingHealthComfort.ready,
  List<OnboardingActivitySymptom> activitySymptoms =
      const <OnboardingActivitySymptom>[OnboardingActivitySymptom.none],
  RecentRunningConsistency recentRunningConsistency =
      RecentRunningConsistency.oneToThreeMonths,
  CurrentWeeklyRunFrequency currentWeeklyRunFrequency =
      CurrentWeeklyRunFrequency.three,
  ContinuousRunCapacity continuousRunCapacity =
      ContinuousRunCapacity.twentyToThirtyMinutes,
  OnboardingPlanStyle planStyle = OnboardingPlanStyle.balanced,
}) {
  return LocalOnboardingDraft(
    goal: goal,
    experience: experience,
    availability: availability,
    preferredDays: preferredDays,
    preferredTime: OnboardingPreferredTime.morning,
    sessionLength: sessionLength,
    runningPlace: OnboardingRunningPlace.park,
    motivationStyle: OnboardingMotivationStyle.plan,
    healthComfort: healthComfort,
    activitySymptoms: activitySymptoms,
    recentRunningConsistency: recentRunningConsistency,
    currentWeeklyRunFrequency: currentWeeklyRunFrequency,
    continuousRunCapacity: continuousRunCapacity,
    planStyle: planStyle,
  );
}
