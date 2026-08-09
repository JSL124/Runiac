import 'package:flutter/material.dart';

import '../onboarding_step_config.dart';
import 'onboarding_option_controls.dart';
import 'onboarding_visuals.dart';

class OnboardingQuestionBody extends StatelessWidget {
  const OnboardingQuestionBody({
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
    final key = step.answerKey!;
    final answer = answers[key];
    final selectedSet = answer is Set<String> ? answer : <String>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (step.help != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              step.help!,
              style: onboardingTextStyle(
                size: 14,
                weight: FontWeight.w500,
                color: onboardingBlueWithOpacity(.60),
                height: 1.5,
              ),
            ),
          ),
        if (helperText != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              helperText!,
              style: onboardingTextStyle(
                size: 13.5,
                weight: FontWeight.w700,
                color: onboardingBlueWithOpacity(.72),
                height: 1.45,
              ),
            ),
          ),
        if (step.banner == OnboardingBannerKind.location) ...[
          const OnboardingInfoBanner(
            icon: Icons.location_on_outlined,
            text:
                'Location permission can be requested later, only when you start a run or use route features.',
          ),
          const SizedBox(height: 14),
        ],
        if (step.banner == OnboardingBannerKind.symptoms) ...[
          const OnboardingInfoBanner(
            icon: Icons.info_outline_rounded,
            text:
                'These answers help Runiac suggest a gentler starting intensity. Select any that apply.',
          ),
          const SizedBox(height: 14),
        ],
        if (step.daysGrid)
          GridView.count(
            crossAxisCount: 4,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.58,
            children: [
              for (final day in onboardingDayNames)
                OnboardingDayChip(
                  label: day,
                  selected: selectedSet.contains(day),
                  onTap: () => onToggleMulti(key, day),
                ),
            ],
          )
        else
          Column(
            children: [
              for (final option in step.options) ...[
                OnboardingOptionTile(
                  label: option.label,
                  sub: option.sub,
                  selected: step.kind == OnboardingStepKind.multi
                      ? selectedSet.contains(option.value)
                      : answers[key] == option.value,
                  multi: step.kind == OnboardingStepKind.multi,
                  onTap: () {
                    if (step.kind == OnboardingStepKind.multi) {
                      onToggleMulti(
                        key,
                        option.value,
                        noneValue: step.noneValue,
                      );
                    } else {
                      onSelectSingle(key, option.value);
                    }
                  },
                ),
                const SizedBox(height: 9),
              ],
            ],
          ),
        if (step.disclaimer) ...[
          const SizedBox(height: 7),
          const OnboardingDisclaimerBanner(),
        ],
      ],
    );
  }
}
