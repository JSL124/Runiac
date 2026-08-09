part of 'xp_update_screen.dart';

class _TotalXpCard extends StatelessWidget {
  const _TotalXpCard({required this.model, required this.stage});

  final XpUpdateDisplayModel model;
  final _XpStage stage;

  @override
  Widget build(BuildContext context) {
    final shownPct = stage.progressFraction;
    final valueLabel = model.totalXp > 0
        ? '${_formatThousands(stage.totalXpShown)} XP'
        : model.totalXpLabel;

    return _XpCardSurface(
      padding: const EdgeInsets.all(16),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const _IconChip(
                color: _blue06,
                icon: Icons.auto_awesome_rounded,
                iconColor: _blue,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total XP',
                      style: TextStyle(
                        color: _blue60,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      valueLabel,
                      style: const TextStyle(
                        color: _blue,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.8,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          _RewardProgressBar(shownPct: shownPct),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  model.progressTargetLabel,
                  style: const TextStyle(
                    color: _blue60,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: _orange,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    model.didLevelUp && stage.showNewLevelBadge
                        ? 'Just leveled up'
                        : model.xpRemainingLabel,
                    style: const TextStyle(
                      color: _blue,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.model, required this.stage});

  final XpUpdateDisplayModel model;
  final _XpStage stage;

  @override
  Widget build(BuildContext context) {
    final increased = model.streakCount > model.previousStreakCount;
    final flameScale = increased ? 1 + 0.15 * stage.streakPulse : 1.0;

    return _XpCardSurface(
      padding: const EdgeInsets.all(16),
      radius: 18,
      child: Row(
        children: [
          Transform.scale(
            scale: flameScale,
            child: const _IconChip(
              color: _orange12,
              icon: Icons.local_fire_department_rounded,
              iconColor: _orange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Day streak',
                  style: TextStyle(
                    color: _blue60,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),
                _streakValue(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The streak value starts as the previous streak ("2 days"); the new value
  /// then stamps down over it — slamming in from a larger scale, squashing the
  /// old label flat on impact, and settling in as the replacement ("3 days").
  Widget _streakValue() {
    const style = TextStyle(
      color: _blue,
      fontSize: 26,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.08,
    );

    if (model.streakCount <= 0) {
      return Text(model.streakChangeLabel, style: style);
    }

    final unit = model.streakCount == 1 ? 'day' : 'days';
    if (model.streakCount <= model.previousStreakCount) {
      return Text('${model.streakCount} $unit', style: style);
    }

    final prevUnit = model.previousStreakCount == 1 ? 'day' : 'days';
    final s = stage.streakTick;

    // Stamp choreography: slam in (0–0.6), crush the old label at impact
    // (0.45–0.65), then a small settle dip (0.7–1.0).
    final slam = Curves.easeInCubic.transform((s / 0.6).clamp(0.0, 1.0));
    final settle = ((s - 0.7) / 0.3).clamp(0.0, 1.0);
    final stampScale =
        _lerp(1.9, 1.0, slam) * (1 - 0.06 * math.sin(settle * math.pi));
    final stampOpacity = (s / 0.35).clamp(0.0, 1.0);
    final crushed = ((s - 0.45) / 0.2).clamp(0.0, 1.0);

    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerLeft,
      children: [
        if (crushed < 1)
          Opacity(
            opacity: 1 - crushed,
            child: Transform(
              transform: Matrix4.diagonal3Values(
                1 + 0.15 * crushed,
                1 - 0.55 * crushed,
                1,
              ),
              alignment: Alignment.bottomLeft,
              child: Text(
                '${model.previousStreakCount} $prevUnit',
                style: style,
              ),
            ),
          ),
        if (stampOpacity > 0)
          Opacity(
            opacity: stampOpacity,
            child: Transform.scale(
              scale: stampScale,
              alignment: Alignment.centerLeft,
              child: Text('${model.streakCount} $unit', style: style),
            ),
          ),
      ],
    );
  }
}

class _GoHomeButton extends StatelessWidget {
  const _GoHomeButton({required this.height, required this.onPressed});

  final double height;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.home_rounded, size: 18),
      label: const Text('Home'),
      style: FilledButton.styleFrom(
        backgroundColor: _blue,
        foregroundColor: _pureWhite,
        minimumSize: Size.fromHeight(height),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontSize: 16.5,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        elevation: 8,
        shadowColor: const Color(0x382F51C8),
      ),
    );
  }
}
