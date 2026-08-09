import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';

class LeaderboardTopOverlay extends StatelessWidget {
  const LeaderboardTopOverlay({
    super.key,
    required this.onShowLeagues,
    required this.onShowTips,
    required this.divisionName,
    required this.levelRange,
    required this.assetPath,
  });

  final VoidCallback onShowLeagues;
  final VoidCallback onShowTips;
  final String divisionName;
  final String levelRange;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LeagueSelector(
            onTap: onShowLeagues,
            divisionName: divisionName,
            levelRange: levelRange,
            assetPath: assetPath,
          ),
        ),
        const SizedBox(width: 10),
        _InfoBadge(onTap: onShowTips),
      ],
    );
  }
}

class _LeagueSelector extends StatelessWidget {
  const _LeagueSelector({
    required this.onTap,
    required this.divisionName,
    required this.levelRange,
    required this.assetPath,
  });

  final VoidCallback onTap;
  final String divisionName;
  final String levelRange;
  final String assetPath;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Open leagues list',
      button: true,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Ink(
              height: 54,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: const Color(0xEFFFFFFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x552F50C7)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x17172033),
                    blurRadius: 12,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                children: [
                  LeaderboardLeagueMedalIcon(
                    key: const Key('leaderboard_current_league_emblem'),
                    assetPath: assetPath,
                    width: 38,
                    height: 38,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      divisionName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    levelRange,
                    style: const TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LeaderboardLeagueMedalIcon extends StatelessWidget {
  const LeaderboardLeagueMedalIcon({
    super.key,
    required this.assetPath,
    this.width = 30,
    this.height = 34,
  });

  final String assetPath;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Image.asset(
        assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Leaderboard information',
      button: true,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xEFFFFFFF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0x552F50C7), width: 1.4),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x17172033),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.info_outline,
                color: RuniacColors.primaryBlue,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
