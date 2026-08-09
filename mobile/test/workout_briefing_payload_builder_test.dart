import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/you/domain/models/workout_briefing_agent.dart';
import 'package:runiac_app/features/you/domain/services/workout_briefing_payload_builder.dart';

const _builder = WorkoutBriefingPayloadBuilder();

WorkoutBriefingRequest _request({
  String dayLabel = 'Thursday · Easy Run',
  String planTitle = 'First Continuous Running Start',
  String effortGuide = 'Keep the effort easy enough to talk in full sentences.',
  int? weekNumber = 3,
  String? weekFocus = 'Build repeatable easy minutes.',
  List<WorkoutBriefingMetric>? metrics,
  List<WorkoutBriefingStep>? steps,
  List<String>? coachNotes,
  String? cacheIdentity = 'plan-1|w3|Thursday · Easy Run',
}) {
  return WorkoutBriefingRequest(
    dayLabel: dayLabel,
    planTitle: planTitle,
    effortGuide: effortGuide,
    weekNumber: weekNumber,
    weekFocus: weekFocus,
    metrics:
        metrics ??
        const [
          WorkoutBriefingMetric(label: 'Distance', value: '3.0 km'),
          WorkoutBriefingMetric(label: 'Time', value: '20 min'),
        ],
    steps:
        steps ??
        const [
          WorkoutBriefingStep(
            title: 'Warm up',
            detail: 'Walk briskly for five minutes.',
          ),
        ],
    coachNotes: coachNotes ?? const ['Start slower than you think.'],
    cacheIdentity: cacheIdentity,
  );
}

void main() {
  group('WorkoutBriefingPayloadBuilder.build', () {
    test('emits only the contract keys and nothing identifying', () {
      final payload = _builder.build(_request());

      expect(payload.keys.toList()..sort(), [
        'coachNotes',
        'metrics',
        'schemaVersion',
        'steps',
        'workout',
      ]);
      expect(payload['schemaVersion'], 1);
      final workout = payload['workout']! as Map<String, Object?>;
      expect(workout.keys.toList()..sort(), [
        'dayLabel',
        'effortGuide',
        'planTitle',
        'weekFocus',
        'weekNumber',
      ]);
      // The plan id is cache-key material only; it must never cross the wire.
      expect(payload.toString(), isNot(contains('plan-1')));
    });

    test('omits optional week context rather than sending placeholders', () {
      final payload = _builder.build(
        _request(weekNumber: null, weekFocus: null),
      );

      final workout = payload['workout']! as Map<String, Object?>;
      expect(workout.containsKey('weekNumber'), isFalse);
      expect(workout.containsKey('weekFocus'), isFalse);
    });

    test('drops a week number outside the supported plan range', () {
      for (final weekNumber in [0, -1, 105]) {
        final workout =
            _builder.build(_request(weekNumber: weekNumber))['workout']!
                as Map<String, Object?>;
        expect(
          workout.containsKey('weekNumber'),
          isFalse,
          reason: 'week $weekNumber should be dropped',
        );
      }
    });

    test('caps every collection at the server contract limit', () {
      final payload = _builder.build(
        _request(
          metrics: List.generate(
            9,
            (index) =>
                WorkoutBriefingMetric(label: 'L$index', value: 'V$index'),
          ),
          steps: List.generate(
            9,
            (index) => WorkoutBriefingStep(title: 'T$index', detail: 'D$index'),
          ),
          coachNotes: List.generate(9, (index) => 'Note $index.'),
        ),
      );

      expect((payload['metrics']! as List).length, 6);
      expect((payload['steps']! as List).length, 6);
      expect((payload['coachNotes']! as List).length, 6);
    });

    test(
      'truncates and collapses text so the server never has to reject it',
      () {
        final payload = _builder.build(
          _request(
            dayLabel: 'x' * 60,
            effortGuide: '  Keep   the effort\n\neasy.  ',
          ),
        );

        final workout = payload['workout']! as Map<String, Object?>;
        expect((workout['dayLabel']! as String).length, 40);
        expect(workout['effortGuide'], 'Keep the effort easy.');
      },
    );
  });

  group('WorkoutBriefingPayloadBuilder.cacheIdentityFor', () {
    test('is null without a caller-supplied plan address', () {
      expect(_builder.cacheIdentityFor(_request(cacheIdentity: null)), isNull);
      expect(_builder.cacheIdentityFor(_request(cacheIdentity: '  ')), isNull);
    });

    test('is stable across identical requests', () {
      expect(
        _builder.cacheIdentityFor(_request()),
        _builder.cacheIdentityFor(_request()),
      );
    });

    test('changes when any part of the briefing content changes', () {
      final baseline = _builder.cacheIdentityFor(_request());

      final variants = <String, WorkoutBriefingRequest>{
        'effortGuide': _request(effortGuide: 'Push a little harder today.'),
        'planTitle': _request(planTitle: 'Consistency Base'),
        'weekNumber': _request(weekNumber: 4),
        'weekFocus': _request(weekFocus: 'Hold one calm rhythm.'),
        'metric': _request(
          metrics: const [
            WorkoutBriefingMetric(label: 'Distance', value: '4.0 km'),
            WorkoutBriefingMetric(label: 'Time', value: '20 min'),
          ],
        ),
        'step': _request(
          steps: const [
            WorkoutBriefingStep(title: 'Warm up', detail: 'Walk ten minutes.'),
          ],
        ),
        'coachNote': _request(coachNotes: const ['Stop if anything hurts.']),
      };

      for (final entry in variants.entries) {
        expect(
          _builder.cacheIdentityFor(entry.value),
          isNot(baseline),
          reason: 'a changed ${entry.key} must invalidate the cache key',
        );
      }
    });

    test('keeps the plan address as a readable prefix', () {
      final identity = _builder.cacheIdentityFor(_request())!;

      expect(identity, startsWith('plan-1|w3|Thursday · Easy Run|'));
      // 64-bit FNV-1a rendered as fixed-width hex.
      expect(identity.split('|').last, matches(RegExp(r'^[0-9a-f]{16}$')));
    });
  });
}
