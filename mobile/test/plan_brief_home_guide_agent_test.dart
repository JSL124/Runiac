import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/home/domain/guide/home_guide_agent.dart';
import 'package:runiac_app/features/home/domain/guide/plan_brief_home_guide_agent.dart';

HomeGuideRequest _request({
  String dayLabel = 'Mon',
  String workoutTitle = 'Easy Run',
  int durationMinutes = 25,
  List<String> steps = const <String>[],
  bool isRestDay = false,
}) {
  return HomeGuideRequest(
    planTitle: 'First 10K Preparation',
    weekNumber: 1,
    weekFocus: 'Build a steady habit',
    dayLabel: dayLabel,
    workoutTitle: workoutTitle,
    durationMinutes: durationMinutes,
    intensityLabel: 'Gentle',
    description: 'A relaxed run to build your habit.',
    steps: steps,
    supportiveNote: 'Keep the pace conversational.',
    isRestDay: isRestDay,
  );
}

String _textOf(HomeGuideContent content) => content.messages.single.text;

void main() {
  group('PlanBriefHomeGuideAgent', () {
    const agent = PlanBriefHomeGuideAgent();

    test('needs no data-use consent because it sends nothing', () {
      expect(agent.requiresDataConsent, isFalse);
    });

    test('answers with exactly one plan-brief message', () async {
      final content = await agent.explainTodayPlan(_request());

      expect(content.messages, hasLength(1));
      expect(content.messages.single.kind, HomeGuideMessageKind.planBrief);
      expect(content.messages.single.isFromRemoteAgent, isFalse);
    });

    test('reads the summary line then the numbered steps', () async {
      final text = _textOf(
        await agent.explainTodayPlan(
          _request(
            steps: <String>[
              'Warm up 5 minutes',
              'Run 15 minutes easy',
              'Cool down 5 minutes',
            ],
          ),
        ),
      );

      expect(text.split('\n'), <String>[
        "Today's Mon session is Easy Run for about 25 minutes.",
        '1. Warm up 5 minutes',
        '2. Run 15 minutes easy',
        '3. Cool down 5 minutes',
      ]);
    });

    test('leaves the summary alone when the plan carries no steps', () async {
      final text = _textOf(await agent.explainTodayPlan(_request()));

      expect(text, "Today's Mon session is Easy Run for about 25 minutes.");
      expect(text, isNot(contains('\n')));
    });

    test('lists at most the step cap', () async {
      final text = _textOf(
        await agent.explainTodayPlan(
          _request(
            steps: List<String>.generate(12, (index) => 'Interval ${index + 1}'),
          ),
        ),
      );

      final lines = text.split('\n');
      expect(lines, hasLength(PlanBriefHomeGuideAgent.maxSteps + 1));
      expect(lines.last, '6. Interval 6');
      expect(text, isNot(contains('Interval 7')));
    });

    test('states the rest day as a fact and lists nothing', () async {
      final text = _textOf(
        await agent.explainTodayPlan(
          _request(
            dayLabel: 'Wed',
            workoutTitle: '',
            durationMinutes: 0,
            steps: const <String>['Should not appear'],
            isRestDay: true,
          ),
        ),
      );

      expect(text, "Today's Wed is a rest day. No session is scheduled.");
      expect(text, isNot(contains('Should not appear')));
    });

    test('drops blank steps and normalizes whitespace', () async {
      final text = _textOf(
        await agent.explainTodayPlan(
          _request(
            steps: const <String>['  ', 'Run   10  minutes', '\n'],
          ),
        ),
      );

      expect(text.split('\n'), <String>[
        "Today's Mon session is Easy Run for about 25 minutes.",
        '1. Run 10 minutes',
      ]);
    });

    test('is deterministic for the same request', () async {
      final request = _request(steps: const <String>['Warm up 5 minutes']);

      expect(
        _textOf(await agent.explainTodayPlan(request)),
        _textOf(await agent.explainTodayPlan(request)),
      );
    });
  });
}
