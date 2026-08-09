part of 'xp_update_screen.dart';

class _RewardProgressBar extends StatelessWidget {
  const _RewardProgressBar({required this.shownPct});

  final double shownPct;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 10,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _blue10),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: shownPct.clamp(0, 1),
              child: const ColoredBox(color: _orange),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.color,
    required this.icon,
    required this.iconColor,
  });

  final Color color;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: iconColor, size: 20),
    );
  }
}

class _XpCardSurface extends StatelessWidget {
  const _XpCardSurface({
    required this.child,
    required this.padding,
    required this.radius,
    this.shadow,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final BoxShadow? shadow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: RuniacColors.cardBorder),
        boxShadow: [
          ?shadow,
          const BoxShadow(
            color: Color(0x0A2F51C8),
            blurRadius: 0,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: child,
    );
  }
}
