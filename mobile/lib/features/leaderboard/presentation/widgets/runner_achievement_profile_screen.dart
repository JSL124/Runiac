import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_back_header.dart';
import '../../../challenge/domain/models/challenge_enums.dart';
import '../../../moderation/data/report_user_writer.dart';
import '../../../moderation/presentation/widgets/report_user_sheet.dart';
import '../../../profile/domain/models/runner_public_profile_read_model.dart';
import '../../../profile/domain/repositories/runner_public_profile_repository.dart';
import '../../../profile/presentation/data/account_profile_demo_snapshots.dart';
import '../../../profile/presentation/level_progress_labels.dart';
import '../../../profile/presentation/widgets/account_challenge_badge_case.dart';
import '../../../profile/presentation/widgets/account_profile_identity.dart';
import '../models/leaderboard_display_models.dart';

/// Another runner's profile, opened from a leaderboard row.
///
/// It shows the same identity card, level gauge, lifetime totals, and badge
/// case the runner sees on their own account screen — and nothing else. The
/// account setup rows, manage rows, and every private profile value stay off
/// this screen, and the backend never sends them here in the first place.
class RunnerAchievementProfileScreen extends StatefulWidget {
  const RunnerAchievementProfileScreen({
    super.key,
    required this.profile,
    required this.onBack,
    this.publicProfileRepository =
        const UnavailableRunnerPublicProfileRepository(),
  });

  /// Rank-row facts already known from the leaderboard (name, rank, region,
  /// level badge, division). They label the screen immediately and remain the
  /// fallback when no public profile source is wired.
  final RunnerAchievementProfileSnapshot profile;
  final VoidCallback onBack;

  /// Backend source for the runner's public running achievements.
  final RunnerPublicProfileRepository publicProfileRepository;

  @override
  State<RunnerAchievementProfileScreen> createState() =>
      _RunnerAchievementProfileScreenState();
}

enum _PublicProfileState { loading, loaded, preview, failed }

class _RunnerAchievementProfileScreenState
    extends State<RunnerAchievementProfileScreen> {
  var _state = _PublicProfileState.loading;
  RunnerPublicProfileReadModel? _publicProfile;
  String _failureMessage = '';

  @override
  void initState() {
    super.initState();
    _loadPublicProfile();
  }

  @override
  void didUpdateWidget(covariant RunnerAchievementProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.snapshotId != widget.profile.snapshotId ||
        oldWidget.profile.rankLabel != widget.profile.rankLabel ||
        oldWidget.profile.buildId != widget.profile.buildId ||
        oldWidget.profile.uid != widget.profile.uid ||
        oldWidget.publicProfileRepository != widget.publicProfileRepository) {
      _loadPublicProfile();
    }
  }

  /// A leaderboard row names the runner by the entry that was tapped — the
  /// backend snapshot carries no uid, so the server resolves the owner and
  /// keeps it. The build id pins the lookup to the board that was on screen,
  /// so a row rendered before a refresh resolves to nobody rather than to
  /// whoever inherited its rank. Every other surface already holds the
  /// runner's uid, so it addresses the profile directly instead.
  RunnerPublicProfileQuery _query() {
    if (widget.profile.snapshotId.isNotEmpty) {
      return RunnerPublicProfileQuery.leaderboardEntry(
        snapshotId: widget.profile.snapshotId,
        rankLabel: widget.profile.rankLabel,
        buildId: widget.profile.buildId,
      );
    }
    return RunnerPublicProfileQuery.runner(uid: widget.profile.uid);
  }

  Future<void> _loadPublicProfile() async {
    final query = _query();
    if (!query.isResolvable) {
      // Demo/preview rows have no backing runner to resolve.
      setState(() {
        _state = _PublicProfileState.preview;
        _publicProfile = null;
      });
      return;
    }
    setState(() {
      _state = _PublicProfileState.loading;
    });
    try {
      final loaded = await widget.publicProfileRepository
          .loadRunnerPublicProfile(query: query);
      if (!mounted) {
        return;
      }
      setState(() {
        _publicProfile = loaded;
        _state = loaded == null
            ? _PublicProfileState.preview
            : _PublicProfileState.loaded;
      });
    } on RunnerPublicProfileFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _publicProfile = null;
        _failureMessage = failure.message;
        _state = _PublicProfileState.failed;
      });
    }
  }

  // Never offer reporting yourself, and never offer it for a profile with no
  // real backing uid — the security rules would reject both anyway, but
  // hiding the affordance keeps the UI honest. A leaderboard row carries no
  // uid and the profile projection deliberately returns none, so reporting a
  // runner reached from the board needs its own server-resolved write before
  // it can be offered here.
  bool get _canReport =>
      !widget.profile.isCurrentUser &&
      widget.profile.uid.isNotEmpty &&
      _currentReporterUid() != null;

  // Guarded the same way activity_route_snapshot_thumbnail_cache.dart guards
  // its own FirebaseAuth.instance read: widget tests that build this screen
  // with static/demo repositories never call Firebase.initializeApp(), so
  // FirebaseAuth.instance itself throws rather than just returning a null
  // user.
  String? _currentReporterUid() {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } on Object {
      return null;
    }
  }

  void _showReportSheet(BuildContext context) {
    final reporterUid = _currentReporterUid();
    if (reporterUid == null) return;
    showReportUserSheet(
      context,
      targetDisplayName: widget.profile.name,
      onSubmit: (reason, description) => reportUser(
        reporterUid: reporterUid,
        targetId: widget.profile.uid,
        reason: reason,
        description: description,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold (not a bare ColoredBox) so this screen keeps a Material
    // ancestor when pushed as its own route; without one, every Text renders
    // with debug yellow underlines.
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Runner profile',
              tooltip: 'Back to Rankings',
              onBack: widget.onBack,
              trailing: _canReport
                  ? Semantics(
                      label: 'Report ${widget.profile.name}',
                      button: true,
                      child: IconButton(
                        key: const Key('runner_profile_report_action'),
                        tooltip: 'Report ${widget.profile.name}',
                        icon: const Icon(
                          Icons.flag_outlined,
                          color: RuniacColors.primaryBlue,
                        ),
                        onPressed: () => _showReportSheet(context),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: _state == _PublicProfileState.loading
                  ? const _RunnerProfileLoadingState()
                  : _buildProfileBody(),
            ),
          ],
        ),
      ),
    );
  }

  /// True when this runner keeps their record private. Asserted by the
  /// backend, which already withheld the values; the guard below is what the
  /// viewer sees, never what enforces it.
  bool get _statsHidden => _publicProfile?.statsHidden ?? false;

  Widget _buildProfileBody() {
    final record = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AccountLevelUpGauge(snapshot: _snapshot()),
        const SizedBox(height: 14),
        AccountLifetimeStats(snapshot: _snapshot()),
        const SizedBox(height: 14),
        AccountChallengeBadgeCase(ownedTierIds: _ownedTierIds()),
      ],
    );
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AccountIdentityCard(snapshot: _snapshot()),
            const SizedBox(height: 14),
            // One guard over the whole record rather than one per card: the
            // cards underneath are already empty (the backend sent no figures
            // for them), and blurring them as a single pane reads as "this
            // section is private" instead of three separate blanks.
            if (_statsHidden)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    record,
                    const Positioned.fill(child: _PrivateRecordGuard()),
                  ],
                ),
              )
            else
              record,
            const SizedBox(height: 14),
            Text(
              _state == _PublicProfileState.failed
                  ? _failureMessage
                  : widget.profile.privacyNote,
              key: const Key('runner_profile_privacy_note'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The runner's earned tiers. `null` keeps the badge case's preview look for
  /// a build with no backend source wired; an empty set (the failed read)
  /// dims every slot rather than implying badges nobody proved.
  Set<ChallengeTierId>? _ownedTierIds() {
    return switch (_state) {
      _PublicProfileState.loaded => _publicProfile?.ownedTierIds,
      _PublicProfileState.failed => const <ChallengeTierId>{},
      _ => null,
    };
  }

  /// Reuses the account snapshot shape so this screen renders through exactly
  /// the same cards the runner sees on their own profile. Backend values win;
  /// the leaderboard row fills the gaps it already knows.
  AccountProfileDemoSnapshot _snapshot() {
    final public = _publicProfile;
    final labels = resolveLevelProgressLabels(
      hasProgress: public != null,
      level: public?.level ?? 0,
      isMaxLevel: public?.isMaxLevel ?? false,
      totalXp: public?.totalXp,
      nextLevelXp: public?.nextLevelXp,
      xpToNextLevel: public?.xpToNextLevel,
    );
    return AccountProfileDemoSnapshot(
      displayName: _firstNonEmpty([public?.displayName, widget.profile.name]),
      avatarInitials: _firstNonEmpty([
        public?.avatarInitials,
        widget.profile.initial,
      ]),
      avatarUrl: _firstNonEmpty([public?.avatarUrl, widget.profile.photoUrl]),
      subscriptionStatusLabel: public?.subscriptionStatusLabel ?? '',
      regionLabel: _firstNonEmpty([
        public?.regionLabel,
        widget.profile.regionLabel,
      ]),
      regionalRankLabel: widget.profile.rankLabel,
      // Once the trusted projection arrives its labels are shown verbatim,
      // even when empty (a runner with no runs yet renders '—'). The
      // leaderboard row's placeholder only stands in before that.
      maxStreakLabel: public == null
          ? widget.profile.bestStreakLabel
          : public.longestStreakLabel,
      totalDistanceLabel: public == null
          ? widget.profile.totalDistanceLabel
          : public.totalDistanceLabel,
      divisionKey: public?.divisionKey ?? '',
      divisionLabel: _firstNonEmpty([
        public?.divisionLabel,
        widget.profile.divisionLabel,
        'Unranked',
      ]),
      previewLevelBadge: _firstNonEmpty([
        public?.levelBadgeLabel,
        widget.profile.levelBadgeLabel,
      ]),
      levelProgressFraction: public?.levelProgressFraction ?? 0,
      nextLevelBadge: labels.nextLevelBadge,
      levelUpCaption: labels.levelUpCaption,
      levelXpSummary: labels.levelXpSummary,
      // Account-only sections stay empty here: this screen never renders the
      // setup, manage, or footer content, and the backend never sends it.
      previewNote: '',
      setupSectionLabel: '',
      manageSectionLabel: '',
      footerCaption: '',
      setupItems: const <AccountProfileInfoItem>[],
      manageRows: const <AccountProfileManageRow>[],
    );
  }

  String _firstNonEmpty(List<String?> candidates) {
    for (final candidate in candidates) {
      final trimmed = candidate?.trim() ?? '';
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return '';
  }
}

/// Frosted pane over a runner's record when they keep it private.
///
/// Styled after the Premium blur guards so the gesture reads as familiar, but
/// it is doing something different: a Premium guard sits on top of real values
/// the viewer's device holds, whereas this one sits on top of empty cards,
/// because `getRunnerPublicProfile` never sent the figures. Removing this
/// widget would reveal blanks, not the runner's record.
class _PrivateRecordGuard extends StatelessWidget {
  const _PrivateRecordGuard();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RuniacColors.white.withValues(alpha: 0.44),
          ),
          child: const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_rounded,
                    size: 22,
                    color: RuniacColors.accentOrange,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Private',
                    key: Key('runner_profile_private_record_guard'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: RuniacColors.accentOrange,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      shadows: [
                        Shadow(color: RuniacColors.white, blurRadius: 10),
                        Shadow(
                          color: RuniacColors.white,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'This runner keeps their running record private.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      shadows: [
                        Shadow(color: RuniacColors.white, blurRadius: 8),
                      ],
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

class _RunnerProfileLoadingState extends StatelessWidget {
  const _RunnerProfileLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          SizedBox(height: 12),
          Text(
            'Loading runner profile...',
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
