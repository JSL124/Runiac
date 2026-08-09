import 'package:flutter/material.dart';

import '../onboarding_step_config.dart';
import 'onboarding_preview_body.dart';
import 'onboarding_question_body.dart';
import 'onboarding_welcome_body.dart';

class OnboardingStepBody extends StatelessWidget {
  const OnboardingStepBody({
    required this.step,
    required this.answers,
    required this.helperText,
    required this.onSelectSingle,
    required this.onToggleMulti,
    super.key,
  });

  final OnboardingStep step;
  final Map<String, Object> answers;
  final String? helperText;
  final void Function(String key, String value) onSelectSingle;
  final void Function(String key, String value, {String? noneValue})
  onToggleMulti;

  @override
  Widget build(BuildContext context) {
    return switch (step.kind) {
      OnboardingStepKind.welcome => const OnboardingWelcomeBody(),
      OnboardingStepKind.preview => OnboardingPreviewBody(answers: answers),
      OnboardingStepKind.single => OnboardingQuestionBody(
        step: step,
        answers: answers,
        helperText: helperText,
        onSelectSingle: onSelectSingle,
        onToggleMulti: onToggleMulti,
      ),
      OnboardingStepKind.multi => OnboardingQuestionBody(
        step: step,
        answers: answers,
        helperText: helperText,
        onSelectSingle: onSelectSingle,
        onToggleMulti: onToggleMulti,
      ),
    };
  }
}
