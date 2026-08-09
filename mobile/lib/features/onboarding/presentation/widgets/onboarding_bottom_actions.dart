import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../onboarding_step_config.dart';
import 'onboarding_visuals.dart';

class OnboardingBottomActions extends StatelessWidget {
  const OnboardingBottomActions({
    required this.step,
    required this.canContinue,
    required this.onPrimary,
    required this.onSecondary,
    this.previewPrimaryLabel,
    this.isSubmitting = false,
    this.errorText,
    super.key,
  });

  final OnboardingStep step;
  final bool canContinue;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  final String? previewPrimaryLabel;
  final bool isSubmitting;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final isWelcome = step.kind == OnboardingStepKind.welcome;
    final isPreview = step.kind == OnboardingStepKind.preview;
    final primaryLabel = switch (step.kind) {
      OnboardingStepKind.welcome => 'Start setup',
      OnboardingStepKind.preview =>
        isSubmitting
            ? 'Saving profile...'
            : previewPrimaryLabel ?? 'Continue with this plan',
      OnboardingStepKind.single => 'Continue',
      OnboardingStepKind.multi => 'Continue',
    };
    final secondaryLabel = isPreview ? 'Edit answers' : null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: onboardingSurfaceWhite,
        border: Border(top: BorderSide(color: onboardingBlueWithOpacity(.10))),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (errorText != null) ...[
                Text(
                  errorText!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: RuniacColors.accentOrange,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: canContinue ? onPrimary : null,
                  style: RuniacButtonStyles.primary(
                    tone: isWelcome || isPreview
                        ? RuniacButtonTone.orange
                        : RuniacButtonTone.blue,
                    disabledBackgroundColor: onboardingBlueWithOpacity(.18),
                    disabledForegroundColor: RuniacColors.white,
                    shape: const StadiumBorder(),
                    textStyle: onboardingTextStyle(
                      size: 16.5,
                      weight: FontWeight.w700,
                      color: RuniacColors.white,
                    ),
                  ),
                  child: Text(primaryLabel),
                ),
              ),
              if (secondaryLabel != null)
                SizedBox(
                  height: 44,
                  child: TextButton(
                    onPressed: onSecondary,
                    style: RuniacButtonStyles.ghost(
                      foregroundColor: onboardingBlueWithOpacity(.75),
                      textStyle: onboardingTextStyle(
                        size: 14.5,
                        weight: FontWeight.w600,
                        color: onboardingBlueWithOpacity(.75),
                      ),
                    ),
                    child: Text(secondaryLabel),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
