import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';

const onboardingSurfaceWhite = Color(0xFFF8FAFF);

Color onboardingBlueWithOpacity(double opacity) {
  return RuniacColors.primaryBlue.withValues(alpha: opacity);
}

TextStyle onboardingTextStyle({
  required double size,
  required FontWeight weight,
  required Color color,
  double? height,
}) {
  return TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: 0,
  );
}

class OnboardingInfoBanner extends StatelessWidget {
  const OnboardingInfoBanner({
    required this.icon,
    required this.text,
    super.key,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return _Banner(
      icon: icon,
      text: text,
      backgroundColor: onboardingBlueWithOpacity(.06),
      iconColor: onboardingBlueWithOpacity(.60),
      textColor: onboardingBlueWithOpacity(.75),
    );
  }
}

class OnboardingDisclaimerBanner extends StatelessWidget {
  const OnboardingDisclaimerBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return _Banner(
      icon: Icons.health_and_safety_outlined,
      text:
          'Runiac is not a medical service. If you have pain, symptoms, or health concerns, speak with a healthcare professional before starting or increasing exercise.',
      backgroundColor: onboardingBlueWithOpacity(.03),
      iconColor: onboardingBlueWithOpacity(.60),
      textColor: onboardingBlueWithOpacity(.75),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.backgroundColor,
    required this.iconColor,
    required this.textColor,
  });

  final IconData icon;
  final String text;
  final Color backgroundColor;
  final Color iconColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: onboardingBlueWithOpacity(.10)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              text,
              style: onboardingTextStyle(
                size: 12.5,
                weight: FontWeight.w500,
                color: textColor,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
