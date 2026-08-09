import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/characters/runner_character.dart';
import '../domain/guide/onboarding_guide_agent.dart';
import '../domain/guide/rule_based_onboarding_guide_agent.dart';
import '../domain/models/local_onboarding_draft.dart';
import '../domain/services/safety_gate_resolver.dart';
import 'onboarding_guide_overlay.dart';
import 'onboarding_step_config.dart';
import 'onboarding_steps.dart';
import 'widgets/onboarding_bottom_actions.dart';
import 'widgets/onboarding_progress_header.dart';
import 'widgets/onboarding_step_body.dart';
import 'widgets/onboarding_visuals.dart';

typedef OnboardingCompleteCallback =
    Future<bool> Function(LocalOnboardingDraft draft);

/// Default idle time on a step before the guide character appears.
const onboardingGuideStallThreshold = Duration(seconds: 12);

class OnboardingFlowScreen extends StatefulWidget {
  const OnboardingFlowScreen({
    required this.onComplete,
    this.guideStallThreshold = onboardingGuideStallThreshold,
    this.guideAgent = const RuleBasedOnboardingGuideAgent(),
    super.key,
  });

  final OnboardingCompleteCallback onComplete;

  /// How long the user may linger on a step before the guide pops in. Reset on
  /// any answer interaction or step change.
  final Duration guideStallThreshold;

  /// Seam that produces the guide's hint copy for the current step.
  final OnboardingGuideAgent guideAgent;

  @override
  State<OnboardingFlowScreen> createState() => _OnboardingFlowScreenState();
}

class _OnboardingFlowScreenState extends State<OnboardingFlowScreen> {
  final _scrollController = ScrollController();
  final Map<String, Object> _answers = {};
  int _stepIndex = 0;
  bool _completing = false;
  String? _completionError;

  Timer? _stallTimer;
  final Set<String> _guideShownStepIds = <String>{};
  String? _guideMessage;
  int _guideRequestSerial = 0;

  OnboardingStep get _step => onboardingSteps[_stepIndex];

  int? get _requiredPreferredDays {
    final availability = OnboardingAvailability.fromValue(
      _answers['availability'] as String?,
    );
    if (availability == null) {
      return null;
    }
    return requiredPreferredDayCountForAvailability(availability);
  }

  @override
  void initState() {
    super.initState();
    _restartStallTimer();
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _restartStallTimer() {
    _stallTimer?.cancel();
    if (widget.guideStallThreshold <= Duration.zero) {
      return;
    }
    _stallTimer = Timer(widget.guideStallThreshold, _onStallThresholdReached);
  }

  /// Reset on any answer interaction: the user is engaged, so hold the guide.
  void _registerInteraction() {
    _restartStallTimer();
  }

  /// Reset when moving between steps and clear any visible guide so the next
  /// step can offer its own hint.
  void _onStepChanged() {
    if (_guideMessage != null) {
      _guideMessage = null;
    }
    _restartStallTimer();
  }

  void _onStallThresholdReached() {
    final stepId = _step.id;
    if (_guideMessage != null || _guideShownStepIds.contains(stepId)) {
      return;
    }
    _guideShownStepIds.add(stepId);
    unawaited(_loadGuideMessage(stepId));
  }

  Future<void> _loadGuideMessage(String stepId) async {
    final serial = ++_guideRequestSerial;
    final step = _step;
    final message = await widget.guideAgent.guide(
      OnboardingGuideRequest(
        stepId: step.id,
        stepTitle: step.title,
        stepHelp: step.help,
        optionLabels: step.options
            .map((option) => option.label)
            .toList(growable: false),
        answersSoFar: Map<String, Object>.of(_answers),
      ),
    );
    if (!mounted || serial != _guideRequestSerial || _step.id != stepId) {
      return;
    }
    setState(() {
      _guideMessage = message.text;
    });
  }

  void _dismissGuide() {
    if (_guideMessage == null) {
      return;
    }
    setState(() {
      _guideMessage = null;
    });
  }

  RunnerCharacter _guideCharacter() {
    return SelectedRunnerCharacterScope.maybeOf(context)?.selectedOrDefault ??
        RunnerCharacter.blue;
  }

  void _selectSingle(String key, String value) {
    _registerInteraction();
    setState(() {
      _answers[key] = value;
    });
  }

  void _toggleMulti(String key, String value, {String? noneValue}) {
    _registerInteraction();
    final current = Set<String>.from(_answers[key] as Set<String>? ?? {});
    final next = <String>{};

    if (noneValue != null && value == noneValue) {
      if (!current.contains(noneValue)) {
        next.add(noneValue);
      }
    } else {
      next.addAll(current.where((item) => item != noneValue));
      if (current.contains(value)) {
        next.remove(value);
      } else {
        next.add(value);
      }
    }

    setState(() {
      _answers[key] = next;
    });
  }

  void _goNext() {
    setState(() {
      _stepIndex = (_stepIndex + 1).clamp(0, onboardingSteps.length - 1);
    });
    _onStepChanged();
    _resetScroll();
  }

  void _goBack() {
    setState(() {
      _stepIndex = (_stepIndex - 1).clamp(0, onboardingSteps.length - 1);
    });
    _onStepChanged();
    _resetScroll();
  }

  void _editAnswers() {
    setState(() {
      _stepIndex = 1;
    });
    _onStepChanged();
    _resetScroll();
  }

  Future<void> _completeOnboarding() async {
    if (_completing) {
      return;
    }
    final draft = LocalOnboardingDraft.fromAnswers(_answers);
    if (draft == null) {
      return;
    }
    setState(() {
      _completing = true;
      _completionError = null;
    });
    final completed = await widget.onComplete(draft);
    if (!mounted) {
      return;
    }
    setState(() {
      _completing = false;
      _completionError = completed
          ? null
          : 'We could not save your profile. Try again.';
    });
  }

  void _resetScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  bool get _canContinue {
    final step = _step;
    if (step.kind == OnboardingStepKind.single) {
      return _answers[step.answerKey] != null;
    }
    if (step.daysGrid) {
      final requiredDays = _requiredPreferredDays;
      final selectedDays = _answers[step.answerKey] as Set<String>? ?? {};
      return requiredDays != null && selectedDays.length >= requiredDays;
    }
    if (step.kind == OnboardingStepKind.multi && step.noneValue != null) {
      // A multi-select that offers an explicit "none of these" option is a
      // safety-style screen: leaving it untouched must not silently pass as
      // an answer, because an empty selection is otherwise indistinguishable
      // from a deliberate "no symptoms" pick downstream (SafetyGateResolver
      // treats absent and empty answers the same way). Require the user to
      // tap something — including "none of these" — before continuing.
      final selected = _answers[step.answerKey] as Set<String>? ?? {};
      return selected.isNotEmpty;
    }
    return true;
  }

  bool get _showsClearancePreview {
    if (_step.kind != OnboardingStepKind.preview) {
      return false;
    }
    final draft = LocalOnboardingDraft.fromAnswers(_answers);
    return draft != null &&
        const SafetyGateResolver().resolve(draft) ==
            SafetyGateState.needsClearance;
  }

  @override
  Widget build(BuildContext context) {
    final step = _step;
    final requiredPreferredDays = _requiredPreferredDays;

    final guideMessage = _guideMessage;

    return Scaffold(
      backgroundColor: onboardingSurfaceWhite,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                OnboardingProgressHeader(
                  stepIndex: _stepIndex,
                  stepCount: onboardingSteps.length,
                  title: step.title,
                  onBack: _stepIndex == 0 ? null : _goBack,
                ),
                Expanded(
                  child: SingleChildScrollView(
                    key: ValueKey('onboarding_scroll_${step.id}'),
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    child: OnboardingStepBody(
                      step: step,
                      answers: _answers,
                      helperText: step.daysGrid && requiredPreferredDays != null
                          ? 'Choose at least $requiredPreferredDays days that usually work for you.'
                          : null,
                      onSelectSingle: _selectSingle,
                      onToggleMulti: _toggleMulti,
                    ),
                  ),
                ),
                OnboardingBottomActions(
                  step: step,
                  canContinue: _canContinue && !_completing,
                  onPrimary: switch (step.kind) {
                    OnboardingStepKind.welcome => _goNext,
                    OnboardingStepKind.preview => _completeOnboarding,
                    OnboardingStepKind.single => _goNext,
                    OnboardingStepKind.multi => _goNext,
                  },
                  onSecondary: switch (step.kind) {
                    OnboardingStepKind.preview => _editAnswers,
                    OnboardingStepKind.welcome => null,
                    OnboardingStepKind.single => null,
                    OnboardingStepKind.multi => null,
                  },
                  previewPrimaryLabel: _showsClearancePreview
                      ? 'Finish for now'
                      : null,
                  isSubmitting: _completing,
                  errorText: _completionError,
                ),
              ],
            ),
            if (guideMessage != null)
              OnboardingGuideOverlay(
                key: ValueKey('onboarding_guide_${step.id}'),
                character: _guideCharacter(),
                message: guideMessage,
                onDismiss: _dismissGuide,
              ),
          ],
        ),
      ),
    );
  }
}
