import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import 'onboarding_visuals.dart';

class OnboardingWelcomeBody extends StatelessWidget {
  const OnboardingWelcomeBody({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final logoWidth = constraints.maxWidth * .67;

        return Column(
          children: [
            const SizedBox(height: 112),
            SizedBox(
              width: logoWidth,
              height: 96,
              child: Image.asset(
                'assets/images/splash/runiac_splash_logo.png',
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 44),
            Text(
              'Welcome to Runiac',
              textAlign: TextAlign.center,
              style: onboardingTextStyle(
                size: 32,
                weight: FontWeight.w800,
                color: RuniacColors.primaryBlue,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Let's set up your first beginner running plan.",
              textAlign: TextAlign.center,
              style: onboardingTextStyle(
                size: 15.5,
                weight: FontWeight.w500,
                color: onboardingBlueWithOpacity(.75),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            const OnboardingInfoBanner(
              icon: Icons.auto_awesome_rounded,
              text:
                  'A quick setup with gentle questions. You can edit answers later, and no location permission is needed now.',
            ),
          ],
        );
      },
    );
  }
}
