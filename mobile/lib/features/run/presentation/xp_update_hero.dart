part of 'xp_update_screen.dart';

class _HeroRewardCard extends StatelessWidget {
  const _HeroRewardCard({
    required this.model,
    required this.stage,
    required this.tokens,
    required this.particles,
    required this.reduceMotion,
  });

  final XpUpdateDisplayModel model;
  final _XpStage stage;
  final _XpLayoutTokens tokens;
  final List<_ConfettiParticle> particles;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final confettiExtent = tokens.ring + 76;
    final showConfetti = !reduceMotion && model.isAwarded && stage.confetti < 1;

    return _XpCardSurface(
      radius: 24,
      padding: EdgeInsets.fromLTRB(20, tokens.heroY, 20, compactBottom),
      shadow: const BoxShadow(
        color: Color(0x1A2F51C8),
        blurRadius: 34,
        offset: Offset(0, 14),
      ),
      child: Column(
        children: [
          Text(
            _heroTitle(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _blue,
              fontSize: 25,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1.15,
            ),
          ),
          SizedBox(height: tokens.titleGap),
          SizedBox(
            width: confettiExtent,
            height: confettiExtent,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                if (showConfetti)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _ConfettiPainter(
                        particles: particles,
                        progress: stage.confetti,
                      ),
                    ),
                  ),
                _LevelRing(
                  model: model,
                  progress: stage.progressFraction,
                  ringSize: tokens.ring,
                  avatarSize: tokens.avatar,
                  showBadge: model.level > 0,
                  badgeLabel: _badgeLabel(),
                  badgeScale: stage.levelBadgeScale,
                ),
                if (model.didLevelUp)
                  Positioned(
                    top: 0,
                    child: Opacity(
                      opacity: stage.levelUpChipOpacity,
                      child: const _LevelUpChip(),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: tokens.xpTopGap),
          _heroBody(),
        ],
      ),
    );
  }

  Widget _heroBody() {
    if (!model.isAwarded) {
      return const SizedBox.shrink();
    }

    return Transform.scale(
      scale: 1 + 0.06 * stage.earnedPop,
      child: Text(
        '+${_formatThousands(stage.earnedXpShown)} XP',
        style: TextStyle(
          color: _orange,
          fontSize: tokens.xpGainSize,
          fontWeight: FontWeight.w800,
          letterSpacing: -2.4,
          height: 1,
        ),
      ),
    );
  }

  String _heroTitle() {
    switch (model.xpAwardState) {
      case XpAwardState.awarded:
        return model.didLevelUp
            ? 'Level ${model.levelLabel}, ${model.runnerName}!'
            : 'Nice work, ${model.runnerName}!';
      case XpAwardState.notAwarded:
        return 'Good effort, ${model.runnerName}!';
      case XpAwardState.deferred:
        return 'Run saved, ${model.runnerName}!';
      case XpAwardState.syncPending:
        return 'Run saved locally, ${model.runnerName}!';
    }
  }

  String _badgeLabel() {
    if (model.didLevelUp && !stage.showNewLevelBadge) {
      return 'Lv.${model.previousLevel}';
    }
    return 'Lv.${model.levelLabel}';
  }

  double get compactBottom => tokens.heroY == 14 ? 14 : 18;
}

class _LevelUpChip extends StatelessWidget {
  const _LevelUpChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: _orange,
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33FB6414),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: const Text(
        'Level up!',
        style: TextStyle(
          color: _pureWhite,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
          height: 1,
        ),
      ),
    );
  }
}
