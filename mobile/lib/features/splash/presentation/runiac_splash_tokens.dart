import 'package:flutter/material.dart';

class RuniacSplashTokens {
  const RuniacSplashTokens._();

  static const blue = Color(0xFF2F51C8);
  static const orange = Color(0xFFFB6414);
  static const softWhite = Color(0xFFF8FAFF);
  static const taglineBlue = Color(0x732F51C8);

  static const logoAsset = 'assets/images/splash/runiac_splash_logo.png';
  static const logoWidth = 232.0;
  static const horizontalPadding = 32.0;
  static const logoToDotsGap = 56.0;
  static const dotSize = 9.0;
  static const dotGap = 10.0;
  static const dotMinOpacity = 0.20;
  static const dotMaxOpacity = 1.0;
  static const dotMinScale = 0.85;
  static const dotMaxScale = 1.10;
  static const dotDuration = Duration(milliseconds: 1250);
  static const dotStagger = Duration(milliseconds: 180);

  static const logoFadeDuration = Duration(milliseconds: 900);
  static const logoFadeDelay = Duration(milliseconds: 100);
  static const logoLift = 6.0;

  static const footerText = 'RUN · TRACK · GROW';
  static const footerBottom = 40.0;
  static const footerFontSize = 11.0;
  static const footerLetterSpacing = 1.6;

  static const minVisibleDuration = Duration(milliseconds: 1600);
  static const transitionDuration = Duration(milliseconds: 350);

  static const dotCurve = Curves.easeInOut;
  static const logoCurve = Cubic(0.22, 1, 0.36, 1);
}
