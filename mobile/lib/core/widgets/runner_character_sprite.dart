import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../characters/runner_character.dart';

typedef _AssetBounds = ({
  double canvasWidth,
  double canvasHeight,
  double left,
  double top,
  double right,
  double bottom,
});

/// Renders every selected guide inside Bolt's 193×289 display footprint.
///
/// The transparent bounds differ between assets, so the renderer maps their
/// visible height to Bolt's visible height, preserves the source aspect ratio,
/// and reserves any extra horizontal room required by hair or limbs.
class RunnerCharacterSprite extends StatelessWidget {
  const RunnerCharacterSprite({
    required this.character,
    required this.assetPath,
    required this.width,
    this.imageKey,
    this.filterQuality = FilterQuality.medium,
    this.errorBuilder,
    super.key,
  });

  final RunnerCharacter character;
  final String assetPath;
  final double width;
  final Key? imageKey;
  final FilterQuality filterQuality;
  final ImageErrorWidgetBuilder? errorBuilder;

  static _AssetBounds _assetBounds(String assetPath) {
    return switch (assetPath) {
      'assets/images/characters/blue_idle/blue_runner_idle.gif' => (
        canvasWidth: 193,
        canvasHeight: 289,
        left: 4,
        top: 4,
        right: 188,
        bottom: 285,
      ),
      'assets/images/characters/cap_runner_idle.gif' => (
        canvasWidth: 320,
        canvasHeight: 320,
        left: 82,
        top: 17,
        right: 239,
        bottom: 309,
      ),
      'assets/images/characters/pink_runner_idle.gif' => (
        canvasWidth: 320,
        canvasHeight: 320,
        left: 46,
        top: 10,
        right: 275,
        bottom: 309,
      ),
      'assets/images/characters/purple_runner_idle.gif' => (
        canvasWidth: 320,
        canvasHeight: 320,
        left: 72,
        top: 26,
        right: 250,
        bottom: 309,
      ),
      'assets/images/characters/blue_runner_run_left.gif' ||
      'assets/images/characters/blue_runner_run_right.gif' => (
        canvasWidth: 240,
        canvasHeight: 312,
        left: 15,
        top: 12,
        right: 225,
        bottom: 312,
      ),
      'assets/images/characters/cap_runner_run_left.gif' => (
        canvasWidth: 320,
        canvasHeight: 320,
        left: 65,
        top: 23,
        right: 254,
        bottom: 309,
      ),
      'assets/images/characters/cap_runner_run_right.gif' => (
        canvasWidth: 320,
        canvasHeight: 320,
        left: 66,
        top: 23,
        right: 255,
        bottom: 309,
      ),
      'assets/images/characters/pink_runner_run_left.gif' => (
        canvasWidth: 320,
        canvasHeight: 320,
        left: 52,
        top: 19,
        right: 267,
        bottom: 309,
      ),
      'assets/images/characters/pink_runner_run_right.gif' => (
        canvasWidth: 320,
        canvasHeight: 320,
        left: 53,
        top: 19,
        right: 268,
        bottom: 309,
      ),
      'assets/images/characters/purple_runner_run_left.gif' ||
      'assets/images/characters/purple_runner_run_right.gif' => (
        canvasWidth: 320,
        canvasHeight: 320,
        left: 58,
        top: 22,
        right: 262,
        bottom: 309,
      ),
      'assets/images/characters/blue_runner_front.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 108,
        top: 9,
        right: 253,
        bottom: 280,
      ),
      'assets/images/characters/cap_runner_front.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 112,
        top: 16,
        right: 245,
        bottom: 270,
      ),
      'assets/images/characters/pink_runner_front.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 87,
        top: 14,
        right: 277,
        bottom: 273,
      ),
      'assets/images/characters/purple_runner_front.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 112,
        top: 3,
        right: 277,
        bottom: 278,
      ),
      'assets/images/characters/blue_runner_left.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 102,
        top: 11,
        right: 256,
        bottom: 280,
      ),
      'assets/images/characters/cap_runner_left.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 104,
        top: 41,
        right: 259,
        bottom: 269,
      ),
      'assets/images/characters/pink_runner_left.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 105,
        top: 18,
        right: 282,
        bottom: 273,
      ),
      'assets/images/characters/purple_runner_left.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 93,
        top: 8,
        right: 263,
        bottom: 277,
      ),
      'assets/images/characters/blue_runner_right.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 88,
        top: 13,
        right: 240,
        bottom: 280,
      ),
      'assets/images/characters/cap_runner_right.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 76,
        top: 24,
        right: 234,
        bottom: 269,
      ),
      'assets/images/characters/pink_runner_right.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 57,
        top: 18,
        right: 230,
        bottom: 273,
      ),
      'assets/images/characters/purple_runner_right.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 72,
        top: 8,
        right: 240,
        bottom: 277,
      ),
      'assets/images/characters/blue_runner_back.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 111,
        top: 14,
        right: 242,
        bottom: 280,
      ),
      'assets/images/characters/cap_runner_back.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 111,
        top: 49,
        right: 240,
        bottom: 269,
      ),
      'assets/images/characters/pink_runner_back.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 88,
        top: 19,
        right: 268,
        bottom: 273,
      ),
      'assets/images/characters/purple_runner_back.png' => (
        canvasWidth: 350,
        canvasHeight: 280,
        left: 87,
        top: 3,
        right: 239,
        bottom: 278,
      ),
      _ => (
        canvasWidth: 1,
        canvasHeight: 1,
        left: 0,
        top: 0,
        right: 1,
        bottom: 1,
      ),
    };
  }

  /// Width required to preserve the asset ratio at Bolt's visible height.
  static double layoutWidthFor({
    required String assetPath,
    required double width,
  }) {
    final height = width * 289 / 193;
    final bounds = _assetBounds(assetPath);
    final referenceHeight = height * 281 / 289;
    final visibleHeight = bounds.bottom - bounds.top;
    final scale = referenceHeight / visibleHeight;
    final visibleWidth = (bounds.right - bounds.left) * scale;
    final horizontalInset = width * 4 / 193;
    return math.max(width, visibleWidth + horizontalInset * 2);
  }

  @override
  Widget build(BuildContext context) {
    final height = character.animationHeightForWidth(width);
    final bounds = _assetBounds(assetPath);
    final referenceTop = height * 4 / 289;
    final referenceHeight = height * 281 / 289;
    final visibleWidth = bounds.right - bounds.left;
    final visibleHeight = bounds.bottom - bounds.top;
    final scale = referenceHeight / visibleHeight;
    final naturalVisibleWidth = visibleWidth * scale;
    final layoutWidth = layoutWidthFor(assetPath: assetPath, width: width);
    final imageWidth = bounds.canvasWidth * scale;
    final imageHeight = bounds.canvasHeight * scale;
    final imageLeft =
        (layoutWidth - naturalVisibleWidth) / 2 - bounds.left * scale;
    final imageTop = referenceTop - bounds.top * scale;
    return SizedBox(
      width: layoutWidth,
      height: height,
      child: ClipRect(
        child: Stack(
          children: [
            Positioned(
              left: imageLeft,
              top: imageTop,
              width: imageWidth,
              height: imageHeight,
              child: Image.asset(
                assetPath,
                key: imageKey,
                fit: BoxFit.fill,
                filterQuality: filterQuality,
                errorBuilder: errorBuilder,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
