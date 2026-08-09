import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/coaching_summary_snapshot.dart';

void main() {
  group('CoachingSummarySnapshot', () {
    test('keeps rule-based label while exposing interpretation metadata', () {
      const summary = CoachingSummarySnapshot(
        source: CoachingSummarySource.ruleBased,
        interpretationId: CoachingInterpretationId.steadyEffortInterpretation,
        headline: 'You kept a controlled rhythm',
        message: 'The available pace data stayed fairly steady.',
        bullets: [
          'What went well: Your rhythm looked consistent.',
          'What to improve: Repeat the easy consistency.',
        ],
        nextAction: 'Repeat an easy run with the same relaxed rhythm.',
      );

      expect(summary.sectionTitle, 'Coaching Summary');
      expect(
        summary.interpretationId,
        CoachingInterpretationId.steadyEffortInterpretation,
      );
    });

    test('maps AI source label only from explicit source metadata', () {
      const summary = CoachingSummarySnapshot(
        source: CoachingSummarySource.aiGenerated,
        interpretationId:
            CoachingInterpretationId.basicCompletionInterpretation,
        headline: 'Returned AI headline',
        message: 'Returned AI message.',
        nextAction: 'Use returned copy only.',
      );

      expect(summary.sectionTitle, 'AI Coaching Summary');
    });

    test('returns immutable bullets from the display model', () {
      const summary = CoachingSummarySnapshot(
        source: CoachingSummarySource.ruleBased,
        headline: 'Run completed',
        message: 'This was a completed beginner running effort.',
        bullets: [
          'What went well: You finished a measurable run.',
          'What to improve: Build consistency with easy efforts.',
        ],
        nextAction: 'Keep the next run easy and repeatable.',
      );

      expect(
        () => summary.bullets.add('Unexpected mutation.'),
        throwsUnsupportedError,
      );
      expect(summary.bullets, hasLength(2));
    });
  });
}
