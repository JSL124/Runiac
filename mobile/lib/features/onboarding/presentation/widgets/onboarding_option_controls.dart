import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import 'onboarding_visuals.dart';

class OnboardingOptionTile extends StatelessWidget {
  const OnboardingOptionTile({
    required this.label,
    required this.selected,
    required this.multi,
    required this.onTap,
    this.sub,
    super.key,
  });

  final String label;
  final String? sub;
  final bool selected;
  final bool multi;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: EdgeInsets.fromLTRB(16, sub == null ? 15 : 14, 16, 14),
          decoration: BoxDecoration(
            color: selected
                ? onboardingBlueWithOpacity(.06)
                : RuniacColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? RuniacColors.primaryBlue
                  : onboardingBlueWithOpacity(.10),
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: onboardingBlueWithOpacity(.07),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              _Indicator(selected: selected, multi: multi),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: onboardingTextStyle(
                        size: 15.5,
                        weight: selected ? FontWeight.w700 : FontWeight.w600,
                        color: RuniacColors.primaryBlue,
                      ),
                    ),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        sub!,
                        style: onboardingTextStyle(
                          size: 12.5,
                          weight: FontWeight.w500,
                          color: onboardingBlueWithOpacity(.60),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OnboardingDayChip extends StatelessWidget {
  const OnboardingDayChip({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: selected
            ? RuniacColors.primaryBlue
            : RuniacColors.white,
        foregroundColor: selected
            ? RuniacColors.white
            : RuniacColors.primaryBlue,
        elevation: 0,
        minimumSize: const Size.fromHeight(46),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: selected
            ? BorderSide.none
            : BorderSide(color: onboardingBlueWithOpacity(.18)),
        textStyle: onboardingTextStyle(
          size: 14.5,
          weight: FontWeight.w700,
          color: selected ? RuniacColors.white : RuniacColors.primaryBlue,
        ),
      ),
      child: Text(label),
    );
  }
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.selected, required this.multi});

  final bool selected;
  final bool multi;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: selected ? RuniacColors.primaryBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(multi ? 7 : 11),
        border: Border.all(
          color: selected
              ? RuniacColors.primaryBlue
              : onboardingBlueWithOpacity(.30),
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 15, color: RuniacColors.white)
          : null,
    );
  }
}
