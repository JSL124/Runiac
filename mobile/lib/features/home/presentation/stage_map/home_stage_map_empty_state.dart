part of 'home_stage_map.dart';

class _HomeStageEmptyState extends StatelessWidget {
  const _HomeStageEmptyState();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          _kEmptyStateBackground,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (context, error, stackTrace) =>
              const ColoredBox(color: Color(0xFFBFE3F5)),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x22000000), Color(0x88000000)],
            ),
          ),
        ),
        Align(
          alignment: const Alignment(0, 0.35),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.hiking_rounded, color: Colors.white, size: 52),
                SizedBox(height: 14),
                Text(
                  'Your journey map is waiting',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Finish your plan setup to unlock a weekly map of gentle running stages.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xE6FFFFFF),
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Speech-bubble card for the Home guide character.
///
/// Display-only: renders the current local guide-cycle message and never
/// touches XP, level, rank, streak, or leaderboard values.
