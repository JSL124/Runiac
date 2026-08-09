part of 'home_stage_map.dart';

class _StageStoneWidget extends StatelessWidget {
  const _StageStoneWidget({
    super.key,
    required this.stone,
    required this.size,
    this.pulse,
    this.onTap,
  });

  final HomeStageStone stone;
  final double size;
  final Listenable? pulse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final asset = stone.isRun ? _kStageRunAsset : _kStageRestAsset;
    final isFuture = stone.state == HomeStageStoneState.future;
    final isCompleted = stone.state == HomeStageStoneState.completed;
    final isMissed = stone.state == HomeStageStoneState.missed;

    Widget image = Image.asset(
      asset,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) {
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: stone.isRun
                ? const Color(0xFFEBC66A)
                : const Color(0xFFBFC7D1),
          ),
        );
      },
    );

    if (isFuture || isMissed) {
      image = Opacity(
        opacity: isMissed ? 0.48 : 0.62,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix(<double>[
            0.45,
            0.45,
            0.10,
            0,
            0,
            0.45,
            0.45,
            0.10,
            0,
            0,
            0.45,
            0.45,
            0.10,
            0,
            0,
            0,
            0,
            0,
            1,
            0,
          ]),
          child: image,
        ),
      );
    }

    Widget content = SizedBox(width: size, height: size, child: image);

    if (isCompleted && stone.isRun) {
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(
            right: -2,
            top: -2,
            child: _CompletedCheck(size: size * 0.34),
          ),
        ],
      );
    }

    if (isMissed && stone.isRun) {
      content = Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          Positioned(right: -2, top: -2, child: _MissedMark(size: size * 0.34)),
        ],
      );
    }

    if (stone.isCurrent && pulse != null) {
      content = AnimatedBuilder(
        animation: pulse!,
        builder: (context, child) {
          final t = pulse is Animation<double>
              ? (pulse! as Animation<double>).value
              : 0.0;
          return Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: 1.0 + 0.22 * t,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(
                      0xFFFC6818,
                    ).withValues(alpha: 0.30 * (1 - t)),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: content,
      );
    }

    if (onTap == null) {
      if (isMissed) {
        return Semantics(label: 'Missed stage', child: content);
      }
      return content;
    }
    return Semantics(
      button: true,
      label: "Today's stage",
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: content,
      ),
    );
  }
}

/// Small English weekday caption pinned to the lower edge of a stage stone.
///
/// Purely cosmetic/display layer: it never intercepts taps (the caller wraps
/// it in [IgnorePointer]) and carries no backend-owned scheduling meaning.
class _StageDayLabel extends StatelessWidget {
  const _StageDayLabel({required this.label, required this.dimmed, super.key});

  final String label;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Opacity(
        opacity: dimmed ? 0.55 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: 0.3,
              shadows: [
                Shadow(
                  color: Colors.black87,
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CompletedCheck extends StatelessWidget {
  const _CompletedCheck({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF2FBF71),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(Icons.check_rounded, size: size * 0.72, color: Colors.white),
    );
  }
}

class _MissedMark extends StatelessWidget {
  const _MissedMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: RuniacColors.textSecondary,
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Icon(Icons.remove_rounded, size: size * 0.72, color: Colors.white),
    );
  }
}
