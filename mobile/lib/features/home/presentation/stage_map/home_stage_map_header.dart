part of 'home_stage_map.dart';

class _HomeStageHeader extends StatelessWidget {
  const _HomeStageHeader({
    required this.levelBadgeLabel,
    required this.levelProgressFraction,
    required this.progressLoading,
    required this.profileLoading,
    required this.profileInitials,
    this.profilePhotoUrl = '',
    required this.onProfile,
    required this.menuOpen,
    required this.menuAnimation,
    required this.onToggleMenu,
    required this.activeChallenge,
    required this.onOpenChallengeProgress,
    required this.challengeClock,
    required this.challengeTicker,
  });

  final String levelBadgeLabel;
  final double levelProgressFraction;
  final bool progressLoading;
  final bool profileLoading;
  final String profileInitials;

  /// Raw, not-yet-sanitised avatar photo URL. Empty renders the initials disc.
  final String profilePhotoUrl;
  final VoidCallback onProfile;
  final bool menuOpen;
  final Animation<double> menuAnimation;
  final VoidCallback onToggleMenu;
  final HomeActiveChallengeDisplay? activeChallenge;
  final VoidCallback? onOpenChallengeProgress;
  final DateTime Function()? challengeClock;
  final ChallengeTicker? challengeTicker;

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return IgnorePointer(
      ignoring: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, topPadding + 8, 12, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              RuniacColors.textPrimary.withValues(alpha: 0.72),
              RuniacColors.textPrimary.withValues(alpha: 0.08),
              Colors.transparent,
            ],
          ),
        ),
        // Top-aligned so the active-challenge badge and the profile disc — both
        // 62px tall — share a y-baseline across the header.
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activeChallenge != null)
              _HomeActiveChallengeControl(
                display: activeChallenge!,
                onOpen: onOpenChallengeProgress,
                clock: challengeClock,
                ticker: challengeTicker,
              ),
            const Spacer(),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TutorialAnchor(
                  id: TutorialAnchorId.homeLevelAvatar,
                  child: Semantics(
                    container: true,
                    label: 'Profile',
                    button: true,
                    child: ExcludeSemantics(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onProfile,
                        child: SizedBox(
                          width: 60,
                          height: 62,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.topCenter,
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: _homeStageControlDecoration(
                                  shape: BoxShape.circle,
                                ),
                              ),
                              if (progressLoading || profileLoading)
                                const _LoadingProfileBadge()
                              else
                                RuniacLevelProfileBadge(
                                  initials: profileInitials,
                                  levelLabel: levelBadgeLabel,
                                  progressFraction: levelProgressFraction,
                                  photoUrl: profilePhotoUrl,
                                  size: 54,
                                  badgeHeight: 17,
                                  badgeMinWidth: 44,
                                  badgeHorizontalPadding: 7,
                                  badgeFontSize: 10,
                                  ringStrokeWidth: 4.5,
                                  discColor: RuniacColors.primaryBlue,
                                  discBorderColor: RuniacColors.white,
                                  initialsColor: RuniacColors.white,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                _HomeMenuTrigger(
                  open: menuOpen,
                  animation: menuAnimation,
                  onTap: onToggleMenu,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Circular header control shown under the Streak pill while a challenge is
/// ACTIVE or SETTLING. The whole badge + countdown area is ONE semantic button
/// that opens Progress; it contains only the tier badge PNG and a fixed-width
/// `DD:HH:MM:SS` countdown (or the short "Calculating…" copy while settling).
/// No title, distance, percent, participant count, progress bar, or chevron.
