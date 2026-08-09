import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/characters/runner_character.dart';
import '../../../../core/widgets/runner_character_sprite.dart';

/// The selected guide character idling beside the paywall feature card,
/// peeking at it like it can't wait for the runner to join Premium.
///
/// Each character plays its idle GIF. Bumping [celebrateTick] plays a single
/// celebratory hop (used when the CTA is tapped). With reduced motion enabled,
/// every character renders as a static front sprite and no controller runs, so
/// `pumpAndSettle`-based tests always settle.
class PaywallCharacterIdle extends StatefulWidget {
  const PaywallCharacterIdle({
    required this.character,
    this.width = 92,
    this.celebrateTick = 0,
    super.key,
  });

  final RunnerCharacter character;
  final double width;

  /// Increment to trigger one celebratory hop.
  final int celebrateTick;

  @override
  State<PaywallCharacterIdle> createState() => _PaywallCharacterIdleState();
}

class _PaywallCharacterIdleState extends State<PaywallCharacterIdle>
    with TickerProviderStateMixin {
  late final AnimationController _hopController;
  var _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    // Finite one-shot hop so the widget always settles when idle.
    _hopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    _reduceMotion = reduceMotion;
  }

  @override
  void didUpdateWidget(covariant PaywallCharacterIdle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.celebrateTick != widget.celebrateTick && !_reduceMotion) {
      _hopController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _hopController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final character = widget.character;
    final useIdleGif = !_reduceMotion;
    final width = widget.width;
    // Bottom-aligned inside a stable box: every character's feet land on the
    // same line, so the sheet's overlap onto the feature card stays identical.
    final sprite = RunnerCharacterSprite(
      character: character,
      assetPath: useIdleGif
          ? character.idleAnimationAssetPath
          : character.assetPath(RunnerCharacterFacing.front),
      width: width,
      imageKey: const Key('paywall-character-sprite'),
    );

    if (_reduceMotion) {
      return sprite;
    }

    return AnimatedBuilder(
      animation: _hopController,
      child: sprite,
      builder: (context, child) {
        // One smooth up-and-down arc for the celebratory hop.
        final hopOffset = -10 * math.sin(_hopController.value * math.pi);
        return Transform.translate(offset: Offset(0, hopOffset), child: child);
      },
    );
  }
}
