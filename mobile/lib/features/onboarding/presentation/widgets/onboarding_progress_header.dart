import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import 'onboarding_visuals.dart';

class OnboardingProgressHeader extends StatelessWidget {
  const OnboardingProgressHeader({
    required this.stepIndex,
    required this.stepCount,
    required this.title,
    required this.onBack,
    super.key,
  });

  final int stepIndex;
  final int stepCount;
  final String? title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final title = this.title;

    return DecoratedBox(
      decoration: const BoxDecoration(color: onboardingSurfaceWhite),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 36,
              child: Row(
                children: [
                  if (onBack != null) ...[
                    IconButton(
                      key: const ValueKey('onboarding_back_button'),
                      tooltip: 'Back',
                      onPressed: onBack,
                      icon: const Icon(
                        Icons.chevron_left_rounded,
                        color: RuniacColors.primaryBlue,
                        size: 30,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(
                        width: 32,
                        height: 32,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    'Step ${stepIndex + 1} of $stepCount',
                    style: onboardingTextStyle(
                      size: 13,
                      weight: FontWeight.w600,
                      color: onboardingBlueWithOpacity(.60),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: (stepIndex + 1) / stepCount,
                minHeight: 6,
                backgroundColor: onboardingBlueWithOpacity(.10),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  RuniacColors.primaryBlue,
                ),
              ),
            ),
            if (title != null) ...[
              const SizedBox(height: 20),
              Text(
                title,
                style: onboardingTextStyle(
                  size: 25,
                  weight: FontWeight.w800,
                  color: RuniacColors.primaryBlue,
                  height: 1.18,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
