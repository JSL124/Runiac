import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/onboarding/domain/models/local_onboarding_draft.dart';

void main() {
  group('LocalOnboardingDraft', () {
    test('maps imported onboarding answer values into typed local enums', () {
      final draft = LocalOnboardingDraft.fromAnswers({
        'goal': '5k',
        'experience': 'new',
        'availability': '3',
        'days': {'Mon', 'Wed', 'Sat'},
        'time': 'morning',
        'length': '20',
        'place': 'park',
        'motivation': 'reminders',
        'health': 'ready',
        'symptoms': {'none'},
        'consistency': 'none',
        'frequency': '0',
        'capacity': 'walk',
        'style': 'balanced',
      });

      expect(draft, isNotNull);
      expect(draft!.goal, OnboardingGoal.first5k);
      expect(draft.experience, OnboardingExperience.newRunner);
      expect(draft.availability, OnboardingAvailability.three);
      expect(draft.preferredDays, [
        OnboardingPreferredDay.mon,
        OnboardingPreferredDay.wed,
        OnboardingPreferredDay.sat,
      ]);
      expect(draft.preferredTime, OnboardingPreferredTime.morning);
      expect(draft.sessionLength, OnboardingSessionLength.twenty);
      expect(draft.runningPlace, OnboardingRunningPlace.park);
      expect(draft.motivationStyle, OnboardingMotivationStyle.reminders);
      expect(draft.healthComfort, OnboardingHealthComfort.ready);
      expect(draft.activitySymptoms, [OnboardingActivitySymptom.none]);
      expect(draft.recentRunningConsistency, RecentRunningConsistency.none);
      expect(draft.currentWeeklyRunFrequency, CurrentWeeklyRunFrequency.zero);
      expect(draft.continuousRunCapacity, ContinuousRunCapacity.walkOnly);
      expect(draft.planStyle, OnboardingPlanStyle.balanced);
      expect(draft.hasCautionIntent, isFalse);
      expect(draft.requestedWeeklySessionCount, 3);
      expect(draft.preferredDurationMinutes, 20);
    });

    test('treats mixed none and symptom answers conservatively', () {
      final draft = LocalOnboardingDraft.fromAnswers({
        'goal': 'habit',
        'experience': 'walk',
        'availability': 'unsure',
        'days': {'Tue'},
        'time': 'flexible',
        'length': 'unsure',
        'place': 'mixed',
        'motivation': 'plan',
        'health': 'unsure',
        'symptoms': {'chest', 'none'},
        'consistency': 'under4',
        'frequency': '1-2',
        'capacity': 'runwalk',
        'style': 'auto',
      });

      expect(draft, isNotNull);
      expect(draft!.activitySymptoms, [OnboardingActivitySymptom.chest]);
      expect(draft.healthComfort, OnboardingHealthComfort.unsure);
      expect(draft.hasCautionIntent, isTrue);
      expect(draft.requestedWeeklySessionCount, 2);
      expect(draft.preferredDurationMinutes, 15);
    });

    test('migrates legacy plan cautiousness answers to plan style', () {
      final baseAnswers = {
        'goal': 'habit',
        'experience': 'walk',
        'availability': '2',
        'days': {'Tue', 'Thu'},
        'time': 'flexible',
        'length': '15',
        'place': 'mixed',
        'motivation': 'plan',
        'health': 'ready',
        'symptoms': {'none'},
        'consistency': '3-6m',
        'frequency': '4',
        'capacity': '45plus',
      };

      final veryGentle = LocalOnboardingDraft.fromAnswers({
        ...baseAnswers,
        'cautious': 'verygentle',
      });
      final standard = LocalOnboardingDraft.fromAnswers({
        ...baseAnswers,
        'cautious': 'standard',
      });
      final unsure = LocalOnboardingDraft.fromAnswers({
        ...baseAnswers,
        'cautious': 'unsure',
      });

      expect(veryGentle!.planStyle, OnboardingPlanStyle.conservativeBase);
      expect(standard!.planStyle, OnboardingPlanStyle.balanced);
      expect(unsure!.planStyle, OnboardingPlanStyle.auto);
    });

    test('treats unanswered symptoms as local caution intent', () {
      final draft = LocalOnboardingDraft.fromAnswers({
        'goal': 'habit',
        'experience': 'walk',
        'availability': '2',
        'days': {'Tue'},
        'time': 'flexible',
        'length': '15',
        'place': 'mixed',
        'motivation': 'plan',
        'health': 'ready',
        'style': 'balanced',
      });

      expect(draft, isNotNull);
      expect(draft!.activitySymptoms, isEmpty);
      expect(draft.recentRunningConsistency, RecentRunningConsistency.none);
      expect(draft.currentWeeklyRunFrequency, CurrentWeeklyRunFrequency.zero);
      expect(draft.continuousRunCapacity, ContinuousRunCapacity.walkOnly);
      expect(draft.hasCautionIntent, isTrue);
    });

    test('returns null when a required single-choice answer is missing', () {
      final draft = LocalOnboardingDraft.fromAnswers({
        'goal': 'habit',
        'experience': 'new',
        'availability': '2',
        'time': 'morning',
        'length': '15',
        'motivation': 'plan',
        'health': 'ready',
      });

      expect(draft, isNull);
    });
  });
}
