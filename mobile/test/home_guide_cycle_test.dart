import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/home/domain/guide/home_guide_agent.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_guide_cycle.dart';

void main() {
  group('HomeGuideCycleController', () {
    test('observes summary, tip, progression, then summary', () async {
      final agent = _ControlledGuideAgent();
      final controller = HomeGuideCycleController(
        agent: agent,
        signature: _signature('stage-1'),
      );
      addTearDown(controller.dispose);

      agent.completeNext(_bundle());
      await controller.settled;

      final observedKinds = <HomeGuideMessageKind>[
        controller.state.currentMessage!.kind,
      ];
      controller.advance();
      observedKinds.add(controller.state.currentMessage!.kind);
      controller.advance();
      observedKinds.add(controller.state.currentMessage!.kind);
      controller.advance();
      observedKinds.add(controller.state.currentMessage!.kind);

      expect(observedKinds, <HomeGuideMessageKind>[
        HomeGuideMessageKind.planSummary,
        HomeGuideMessageKind.runningTip,
        HomeGuideMessageKind.progressionCheckIn,
        HomeGuideMessageKind.planSummary,
      ]);
    });

    test('close and reopen preserve the current message', () async {
      final agent = _ControlledGuideAgent();
      final controller = HomeGuideCycleController(
        agent: agent,
        signature: _signature('stage-1'),
      );
      addTearDown(controller.dispose);

      agent.completeNext(_bundle());
      await controller.settled;
      controller.advance();
      controller.hide();
      controller.advance();
      controller.show();

      expect(controller.state.isVisible, isTrue);
      expect(
        controller.state.currentMessage!.kind,
        HomeGuideMessageKind.runningTip,
      );
    });

    test('loading ignores repeated advances and starts one request', () async {
      final agent = _ControlledGuideAgent();
      final controller = HomeGuideCycleController(
        agent: agent,
        signature: _signature('stage-1'),
      );
      addTearDown(controller.dispose);

      controller.advance();
      controller.advance();
      controller.hide();
      controller.show();

      expect(agent.invocationCount, 1);
      expect(controller.state.isLoading, isTrue);
      expect(controller.state.currentMessage, isNull);
    });

    test('resets only when the stage or request signature changes', () async {
      final agent = _ControlledGuideAgent();
      final firstSignature = _signature('stage-1');
      final controller = HomeGuideCycleController(
        agent: agent,
        signature: firstSignature,
      );
      addTearDown(controller.dispose);

      agent.completeNext(_bundle());
      await controller.settled;
      controller.advance();

      expect(controller.updateSignature(_signature('stage-1')), isFalse);
      expect(
        controller.state.currentMessage!.kind,
        HomeGuideMessageKind.runningTip,
      );

      expect(
        controller.updateSignature(
          _signature('stage-1', workoutTitle: 'Walk and run'),
        ),
        isTrue,
      );
      expect(controller.state.isLoading, isTrue);
      expect(controller.state.currentMessage, isNull);
      agent.completeNext(_bundle());
      await controller.settled;

      expect(
        controller.state.currentMessage!.kind,
        HomeGuideMessageKind.planSummary,
      );

      controller.advance();
      controller.hide();
      expect(controller.updateSignature(_signature('stage-2')), isTrue);
      expect(controller.state.isVisible, isTrue);
      expect(controller.state.currentMessage, isNull);
      agent.completeNext(_bundle());
      await controller.settled;
      expect(
        controller.state.currentMessage!.kind,
        HomeGuideMessageKind.planSummary,
      );
    });

    test('reuses one in-memory bundle future for each signature', () async {
      final agent = _ControlledGuideAgent();
      final firstSignature = _signature('stage-1');
      final secondSignature = _signature('stage-2');
      final controller = HomeGuideCycleController(
        agent: agent,
        signature: firstSignature,
      );
      addTearDown(controller.dispose);

      agent.completeNext(_bundle());
      await controller.settled;
      controller.updateSignature(secondSignature);
      agent.completeNext(_bundle());
      await controller.settled;
      controller.updateSignature(firstSignature);
      await controller.settled;

      expect(agent.invocationCount, 2);
      expect(
        controller.state.currentMessage!.kind,
        HomeGuideMessageKind.planSummary,
      );
    });

    test('a new controller refetches the same signature', () async {
      final agent = _ControlledGuideAgent();
      final signature = _signature('stage-1');
      final firstController = HomeGuideCycleController(
        agent: agent,
        signature: signature,
      );

      agent.completeNext(_bundle());
      await firstController.settled;
      firstController.dispose();

      final secondController = HomeGuideCycleController(
        agent: agent,
        signature: signature,
      );
      addTearDown(secondController.dispose);
      expect(agent.invocationCount, 2);

      agent.completeNext(_bundle());
      await secondController.settled;
    });

    test('a stale bundle cannot overwrite the active signature', () async {
      final agent = _ControlledGuideAgent();
      final controller = HomeGuideCycleController(
        agent: agent,
        signature: _signature('stage-1'),
      );
      addTearDown(controller.dispose);

      controller.updateSignature(_signature('stage-2'));
      agent.completeNext(_bundle(planSummary: 'Old session is ready.'));
      await Future<void>.value();

      expect(controller.state.isLoading, isTrue);
      expect(controller.state.currentMessage, isNull);

      agent.completeNext(_bundle(planSummary: 'New session is ready.'));
      await controller.settled;

      expect(controller.state.currentMessage!.text, 'New session is ready.');
    });
  });
}

HomeGuideCycleSignature _signature(
  String stageId, {
  String workoutTitle = 'Easy Run',
}) {
  return HomeGuideCycleSignature.forRequest(
    stageId: stageId,
    request: HomeGuideRequest(
      planTitle: 'First 10K Preparation',
      weekNumber: 1,
      weekFocus: 'Build a steady habit',
      dayLabel: 'Mon',
      workoutTitle: workoutTitle,
      durationMinutes: 20,
      intensityLabel: 'Gentle',
      description: 'A relaxed run to build your habit.',
    ),
  );
}

HomeGuideBundle _bundle({String planSummary = 'Your session is ready.'}) {
  return HomeGuideBundle(
    planSummary: HomeGuideMessage(
      kind: HomeGuideMessageKind.planSummary,
      text: planSummary,
    ),
    runningTip: const HomeGuideMessage(
      kind: HomeGuideMessageKind.runningTip,
      text: 'Keep your effort comfortable.',
    ),
    progressionCheckIn: const HomeGuideMessage(
      kind: HomeGuideMessageKind.progressionCheckIn,
      text: 'A steady baseline is a strong start.',
    ),
    isFromRemoteAgent: false,
  );
}

class _ControlledGuideAgent implements HomeGuideAgent {
  final List<Completer<HomeGuideBundle>> _pending =
      <Completer<HomeGuideBundle>>[];

  int invocationCount = 0;

  @override
  bool get requiresDataConsent => false;

  @override
  Future<HomeGuideBundle> explainTodayPlan(HomeGuideRequest request) {
    invocationCount += 1;
    final completer = Completer<HomeGuideBundle>();
    _pending.add(completer);
    return completer.future;
  }

  void completeNext(HomeGuideBundle bundle) {
    _pending.removeAt(0).complete(bundle);
  }
}
