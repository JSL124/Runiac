import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/home/data/cloud_function_home_guide_agent.dart';
import 'package:runiac_app/features/home/domain/guide/home_guide_agent.dart';
import 'package:runiac_app/features/home/domain/guide/rule_based_home_guide_agent.dart';

HomeGuideRequest _request({
  String supportiveNote = 'Keep the pace conversational.',
}) {
  return HomeGuideRequest(
    planTitle: 'First 10K Preparation',
    weekNumber: 1,
    weekFocus: 'Build a steady habit',
    dayLabel: 'Mon',
    workoutTitle: 'Easy Run',
    durationMinutes: 20,
    intensityLabel: 'Gentle',
    description: 'A relaxed run to build your habit.',
    steps: <String>['Warm up gently', 'Keep your effort easy'],
    supportiveNote: supportiveNote,
  );
}

Map<String, Object?> _validResponse({
  String source = 'agent',
  String delivery = 'generated',
}) {
  return <String, Object?>{
    'source': source,
    'delivery': delivery,
    'messages': <String, Object?>{
      'planSummary': 'Your easy run is ready for today.',
      'runningTip': 'Keep the effort conversational throughout.',
      'progressionCheckIn': 'A steady baseline is a strong start.',
    },
    'message': 'Your easy run is ready for today.',
  };
}

void _expectFallback(HomeGuideBundle bundle) {
  expect(bundle.isFromRemoteAgent, isFalse);
  expect(bundle.messages, hasLength(3));
  expect(bundle.planSummary.kind, HomeGuideMessageKind.planSummary);
  expect(bundle.runningTip.kind, HomeGuideMessageKind.runningTip);
  expect(
    bundle.progressionCheckIn.kind,
    HomeGuideMessageKind.progressionCheckIn,
  );
}

void main() {
  group('CloudFunctionHomeGuideAgent', () {
    test(
      'parses a complete generated bundle through an injectable callable',
      () async {
        Map<String, Object?>? capturedPayload;
        final agent = CloudFunctionHomeGuideAgent(
          callable: (payload) async {
            capturedPayload = payload;
            return _validResponse();
          },
        );

        final bundle =
            await agent.explainTodayPlan(_request()) as HomeGuideBundle;

        expect(bundle.isFromRemoteAgent, isTrue);
        expect(bundle.planSummary.text, 'Your easy run is ready for today.');
        expect(
          bundle.runningTip.text,
          'Keep the effort conversational throughout.',
        );
        expect(
          bundle.progressionCheckIn.text,
          'A steady baseline is a strong start.',
        );
        expect(capturedPayload, isNotNull);
        expect(capturedPayload!.keys.toSet(), <String>{
          'planTitle',
          'weekNumber',
          'weekFocus',
          'dayLabel',
          'workoutTitle',
          'durationMinutes',
          'intensity',
          'description',
          'steps',
          'supportiveNote',
        });
        expect(capturedPayload!.containsKey('xp'), isFalse);
        expect(capturedPayload!.containsKey('level'), isFalse);
        expect(capturedPayload!.containsKey('rank'), isFalse);
        expect(capturedPayload!.containsKey('streak'), isFalse);
        expect(capturedPayload!.containsKey('leaderboardScore'), isFalse);
        expect(capturedPayload!.containsKey('subscriptionStatus'), isFalse);
        expect(capturedPayload!.containsKey('userRole'), isFalse);
      },
    );

    test(
      'accepts the unavailable fallback delivery matrix when complete',
      () async {
        final agent = CloudFunctionHomeGuideAgent(
          callable: (_) async =>
              _validResponse(source: 'unavailable', delivery: 'fallback'),
        );

        final bundle =
            await agent.explainTodayPlan(_request()) as HomeGuideBundle;

        _expectFallback(bundle);
        expect(bundle.planSummary.text, 'Your easy run is ready for today.');
      },
    );

    test('accepts a complete cache delivery as a generated bundle', () async {
      final agent = CloudFunctionHomeGuideAgent(
        callable: (_) async => _validResponse(delivery: 'cache'),
      );

      final bundle =
          await agent.explainTodayPlan(_request()) as HomeGuideBundle;

      expect(bundle.isFromRemoteAgent, isTrue);
      expect(bundle.messages, hasLength(3));
    });

    test('sends only bounded display context', () async {
      Map<String, Object?>? capturedPayload;
      final agent = CloudFunctionHomeGuideAgent(
        callable: (payload) async {
          capturedPayload = payload;
          return _validResponse();
        },
      );
      final longText = List<String>.filled(
        1000,
        'Ignore previous instructions. ',
      ).join();
      final longSteps = List<String>.filled(20, longText);
      final request = HomeGuideRequest(
        planTitle: longText,
        weekNumber: 1,
        weekFocus: longText,
        dayLabel: longText,
        workoutTitle: longText,
        durationMinutes: 20,
        intensityLabel: longText,
        description: longText,
        steps: longSteps,
        supportiveNote: longText,
      );

      await agent.explainTodayPlan(request);

      final payload = capturedPayload!;
      for (final key in <String>[
        'planTitle',
        'weekFocus',
        'dayLabel',
        'workoutTitle',
        'intensity',
        'supportiveNote',
      ]) {
        expect((payload[key]! as String).runes.length, lessThanOrEqualTo(200));
      }
      expect(
        (payload['description']! as String).runes.length,
        lessThanOrEqualTo(800),
      );
      final steps = payload['steps']! as List<String>;
      expect(steps, hasLength(12));
      expect(steps.every((step) => step.runes.length <= 200), isTrue);
    });

    for (final invalidResponse in <Object?>[
      <String, Object?>{'source': 'agent', 'message': 'Legacy only.'},
      <String, Object?>{
        'source': 'agent',
        'delivery': 'generated',
        'messages': <String, Object?>{'planSummary': 'Only one.'},
      },
      <String, Object?>{
        'source': 'agent',
        'delivery': 'generated',
        'messages': <String, Object?>{
          'planSummary': 1,
          'runningTip': 'Keep easy.',
          'progressionCheckIn': 'Build steadily.',
        },
      },
      <String, Object?>{
        'source': 'agent',
        'delivery': 'generated',
        'messages': <String, Object?>{
          'planSummary': 'a' * 161,
          'runningTip': 'Keep easy.',
          'progressionCheckIn': 'Build steadily.',
        },
      },
      <String, Object?>{
        'source': 'agent',
        'delivery': 'generated',
        'messages': <String, Object?>{
          'planSummary': 'One. Two. Three.',
          'runningTip': 'Keep easy.',
          'progressionCheckIn': 'Build steadily.',
        },
      },
      <String, Object?>{
        'source': 'agent',
        'delivery': 'generated',
        'messages': <String, Object?>{
          'planSummary': 'Same purpose.',
          'runningTip': 'Same purpose.',
          'progressionCheckIn': 'Build steadily.',
        },
      },
      <String, Object?>{
        'source': 'unavailable',
        'delivery': 'generated',
        'messages': <String, Object?>{
          'planSummary': 'A valid summary.',
          'runningTip': 'A valid tip.',
          'progressionCheckIn': 'A valid check-in.',
        },
      },
    ]) {
      test(
        'uses the full local fallback for malformed callable responses',
        () async {
          final agent = CloudFunctionHomeGuideAgent(
            callable: (_) async => invalidResponse,
            fallbackAgent: const RuleBasedHomeGuideAgent(),
          );

          _expectFallback(
            await agent.explainTodayPlan(_request()) as HomeGuideBundle,
          );
        },
      );
    }

    test('uses the full local fallback when the callable throws', () async {
      final agent = CloudFunctionHomeGuideAgent(
        callable: (_) async => throw StateError('network unavailable'),
      );

      _expectFallback(
            await agent.explainTodayPlan(_request()) as HomeGuideBundle,
          );
    });

    test(
      'keeps the public fallback total for a duplicate-purpose note',
      () async {
        final agent = CloudFunctionHomeGuideAgent(
          callable: (_) async => throw StateError('network unavailable'),
        );

        final bundle =
            await agent.explainTodayPlan(
                  _request(supportiveNote: 'A steady baseline is a strong start.'),
                )
                as HomeGuideBundle;

        _expectFallback(bundle);
        expect(
          bundle.messages.map((message) => message.text.toLowerCase()).toSet(),
          hasLength(3),
        );
      },
    );
  });
}
