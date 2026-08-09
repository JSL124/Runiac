import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/haptics/runiac_haptics_scope.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_success_check_overlay.dart';
import '../../auth/domain/runiac_auth_service.dart';
import '../../challenge/domain/models/challenge_enums.dart';
import '../../challenge/domain/models/challenge_history.dart';
import '../../challenge/domain/repositories/challenge_repository.dart';
import '../../challenge/presentation/challenge_ceremony_route.dart';
import '../../challenge/presentation/challenge_result_screen.dart';
import '../../home/domain/guide/home_guide_consent.dart';
import '../../leaderboard/data/static_leaderboard_repository.dart';
import '../../leaderboard/domain/models/leaderboard_read_model.dart';
import '../../leaderboard/domain/repositories/leaderboard_repository.dart';
import '../../plan/domain/repositories/generated_plan_persistence_repository.dart';
import '../../you/domain/models/user_progress_read_model.dart';
import '../../you/domain/repositories/user_progress_repository.dart';
import '../data/avatar/firebase_avatar_upload_gateway.dart';
import '../domain/models/user_profile_read_model.dart';
import '../domain/repositories/user_profile_persistence_repository.dart';
import '../domain/repositories/user_profile_repository.dart';
import 'account_edit_profile_screen.dart';
import 'current_session_user_account.dart';
import 'data/account_profile_demo_snapshots.dart';
import 'level_progress_labels.dart';
import 'widgets/account_challenge_badge_case.dart';
import 'widgets/account_profile_identity.dart';
import 'widgets/account_profile_sections.dart';

class AccountProfileScreen extends StatefulWidget {
  const AccountProfileScreen({
    required this.authRepository,
    required this.profileRepository,
    required this.profilePersistenceRepository,
    required this.generatedPlanPersistenceRepository,
    required this.onBack,
    this.userProgressRepository = const StaticUserProgressRepository(),
    this.leaderboardRepository = const StaticLeaderboardRepository(),
    this.challengeRepository,
    this.snapshot = accountProfileDemoSnapshot,
    this.onNotificationSettingsChanged,
    this.homeGuideConsentRepository =
        const AlwaysGrantedHomeGuideConsentRepository(),
    this.avatarUploadGateway,
    this.avatarPhotoPicker,
    super.key,
  });

  final RuniacAuthRepository authRepository;
  final UserProfileRepository profileRepository;
  final UserProfilePersistenceRepository profilePersistenceRepository;
  final GeneratedPlanPersistenceRepository generatedPlanPersistenceRepository;
  final UserProgressRepository userProgressRepository;
  final LeaderboardRepository leaderboardRepository;

  /// Trusted badge-ownership source for the challenge badge case. When `null`
  /// (default), the badge case keeps its static preview (all badges full
  /// colour). When supplied, the case renders earned vs unearned from the
  /// backend-owned `ownedBadges()` projection.
  final ChallengeRepository? challengeRepository;
  final VoidCallback onBack;
  final AccountProfileDemoSnapshot snapshot;
  final VoidCallback? onNotificationSettingsChanged;

  /// Consent source for the Privacy & Safety personalized-guide control.
  /// Defaults to the always-granted stub for previews/tests; the composition
  /// root threads the Cloud Function-backed repository via `HomeTab`.
  final HomeGuideConsentRepository homeGuideConsentRepository;

  /// Threaded straight through to the pushed [AccountEditProfileScreen];
  /// defaults to null there (which resolves to the production Firebase
  /// gateway). Exposed here only so tests can inject a stub through the full
  /// Account → Edit Profile navigation, exercising the real
  /// `_openEditProfile` refresh contract end-to-end.
  final AvatarUploadGateway? avatarUploadGateway;

  /// See [avatarUploadGateway].
  final AvatarPhotoPicker? avatarPhotoPicker;

  @override
  State<AccountProfileScreen> createState() => _AccountProfileScreenState();
}

class _AccountProfileScreenState extends State<AccountProfileScreen> {
  late Future<UserProfileReadModel> _profileFuture;
  late Future<UserProgressReadModel> _progressFuture;
  late Future<LeaderboardReadModel> _leaderboardFuture;
  StreamSubscription<UserProgressReadModel>? _progressSubscription;
  bool _verificationSendPending = false;
  String? _verificationFeedbackMessage;

  /// Owned tier badges for the badge case. `null` keeps the static preview
  /// (all full colour); a loaded set drives earned/unearned rendering.
  Set<ChallengeTierId>? _ownedTierIds;

  /// The trusted terminal result per earned tier, projected from durable
  /// history, so tapping a collected badge replays its ceremony with the real
  /// backend-owned figures (never synthesized).
  Map<ChallengeTierId, ChallengeResult> _resultByTier =
      const <ChallengeTierId, ChallengeResult>{};

  @override
  void initState() {
    super.initState();
    _profileFuture = widget.profileRepository.loadUserProfile();
    _progressFuture = widget.userProgressRepository.loadUserProgress();
    _leaderboardFuture = widget.leaderboardRepository.loadLeaderboard();
    _subscribeToLiveProgress();
    _loadOwnedBadges();
  }

  /// Loads trusted badge ownership when a challenge source is wired. Degrades
  /// gracefully: a failure leaves every slot unearned rather than blocking the
  /// account screen. Preview mode (no repository) keeps `_ownedTierIds` null.
  Future<void> _loadOwnedBadges() async {
    final repository = widget.challengeRepository;
    if (repository == null) {
      return;
    }
    Set<ChallengeTierId> owned;
    try {
      final ownership = await repository.ownedBadges();
      owned = ownership.ownedTierIds;
    } catch (_) {
      owned = const <ChallengeTierId>{};
    }
    // Durable history gives the trusted result to replay per tier. A failure
    // here only disables badge taps; ownership display still stands.
    final resultByTier = <ChallengeTierId, ChallengeResult>{};
    try {
      for (final entry in await repository.history()) {
        if (entry.outcome == ChallengeParticipantStatus.succeeded) {
          resultByTier.putIfAbsent(entry.tierId, entry.toResult);
        }
      }
    } catch (_) {
      // Leave the map empty; taps simply stay inert.
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _ownedTierIds = owned;
      _resultByTier = resultByTier;
    });
  }

  /// Replays a collected tier's ceremony using the trusted result, with the
  /// same "bloom open" transition as every other ceremony entry point. No
  /// badge-collection action is offered (the viewer is already here).
  void _replayTierCeremony(ChallengeTierId tierId) {
    final result = _resultByTier[tierId];
    if (result == null) {
      return;
    }
    Navigator.of(context).push(
      challengeCeremonyRoute<void>(
        fullscreenDialog: true,
        builder: (routeContext) => ChallengeResultScreen(
          result: result,
          onClose: () => Navigator.of(routeContext).pop(),
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant AccountProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profileRepository != widget.profileRepository) {
      _profileFuture = widget.profileRepository.loadUserProfile();
    }
    if (oldWidget.userProgressRepository != widget.userProgressRepository) {
      _progressFuture = widget.userProgressRepository.loadUserProgress();
      _progressSubscription?.cancel();
      _subscribeToLiveProgress();
    }
    if (oldWidget.leaderboardRepository != widget.leaderboardRepository) {
      _leaderboardFuture = widget.leaderboardRepository.loadLeaderboard();
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToLiveProgress() {
    final repository = widget.userProgressRepository;
    if (repository is! LiveUserProgressRepository) {
      return;
    }
    _progressSubscription = repository.watchUserProgress().listen(
      (progress) {
        if (!mounted) {
          return;
        }
        setState(() {
          _progressFuture = Future.value(progress);
        });
      },
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'runiac account profile',
            context: ErrorDescription('watching backend progression updates'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Profile',
              tooltip: 'Back to Home',
              onBack: widget.onBack,
            ),
            Expanded(
              child: FutureBuilder<UserProfileReadModel>(
                future: _profileFuture,
                builder: (context, asyncProfile) {
                  if (asyncProfile.connectionState == ConnectionState.waiting) {
                    return const _AccountProfileLoadingState();
                  }
                  if (asyncProfile.hasError) {
                    return _AccountProfileRecoveryState(
                      onSetupProfile: _showProfileRecoveryUnavailable,
                    );
                  }
                  return FutureBuilder<UserProgressReadModel>(
                    future: _progressFuture,
                    builder: (context, asyncProgress) {
                      return FutureBuilder<LeaderboardReadModel>(
                        future: _leaderboardFuture,
                        builder: (context, asyncLeaderboard) {
                          return _buildProfileBody(
                            asyncProfile.data,
                            asyncProgress.data,
                            asyncLeaderboard.data,
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileBody(
    UserProfileReadModel? profile,
    UserProgressReadModel? progress,
    LeaderboardReadModel? leaderboard,
  ) {
    // Trusted Basic/Premium tier from the app-level `users/{uid}` listener.
    // Depending on the scope here rebuilds the badge in place when an
    // admin-side subscription change arrives, with no restart or re-login.
    // Empty while unresolved, which hides the badge instead of guessing; the
    // demo fallback is used only when no scope is present (previews/tests).
    final subscriptionStatusLabel =
        CurrentSessionUserAccountScope.maybeOf(
          context,
        )?.subscriptionStatusLabel ??
        widget.snapshot.subscriptionStatusLabel;
    final snapshot = _snapshotFromProfile(
      profile,
      progress,
      leaderboard,
      widget.snapshot,
      subscriptionStatusLabel,
    );
    final currentUser = widget.authRepository.currentUser;
    final showVerificationPrompt =
        currentUser != null &&
        (currentUser.email?.trim().isNotEmpty ?? false) &&
        !currentUser.emailVerified;
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showVerificationPrompt) ...[
              _EmailVerificationPrompt(
                email: currentUser.email!.trim(),
                isPending: _verificationSendPending,
                feedbackMessage: _verificationFeedbackMessage,
                onResend: () {
                  _sendVerificationEmail();
                },
              ),
              const SizedBox(height: 14),
            ],
            AccountIdentityCard(snapshot: snapshot),
            const SizedBox(height: 14),
            AccountLevelUpGauge(snapshot: snapshot),
            const SizedBox(height: 14),
            AccountLifetimeStats(snapshot: snapshot),
            const SizedBox(height: 14),
            AccountChallengeBadgeCase(
              ownedTierIds: widget.challengeRepository == null
                  ? null
                  : (_ownedTierIds ?? const <ChallengeTierId>{}),
              onBadgeTap: widget.challengeRepository == null
                  ? null
                  : _replayTierCeremony,
            ),
            if (snapshot.previewNote.isNotEmpty) ...[
              const SizedBox(height: 14),
              AccountPreviewNote(message: snapshot.previewNote),
            ],
            const SizedBox(height: 22),
            AccountSectionLabel(snapshot.setupSectionLabel),
            const SizedBox(height: 8),
            AccountSetupSection(
              items: snapshot.setupItems,
              note: snapshot.setupNote,
            ),
            const SizedBox(height: 22),
            AccountSectionLabel(snapshot.manageSectionLabel),
            const SizedBox(height: 8),
            AccountManageSection(
              rows: snapshot.manageRows,
              authRepository: widget.authRepository,
              onNotificationSettingsChanged:
                  widget.onNotificationSettingsChanged,
              homeGuideConsentRepository: widget.homeGuideConsentRepository,
              onEditProfile: profile == null
                  ? null
                  : () => _openEditProfile(profile),
            ),
            const SizedBox(height: 22),
            Text(
              snapshot.footerCaption,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendVerificationEmail() async {
    if (_verificationSendPending) {
      return;
    }
    setState(() {
      _verificationSendPending = true;
      _verificationFeedbackMessage = null;
    });
    try {
      await widget.authRepository.sendEmailVerification();
      if (!mounted) {
        return;
      }
      setState(() {
        _verificationFeedbackMessage = 'Verification email sent.';
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Verification email sent.')),
        );
    } on RuniacAuthException catch (error) {
      if (!mounted) {
        return;
      }
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() {
        _verificationFeedbackMessage = error.userMessage;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error.userMessage)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() {
        _verificationFeedbackMessage =
            'We could not send that email. Please try again.';
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('We could not send that email. Please try again.'),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _verificationSendPending = false;
        });
      }
    }
  }

  void _showProfileRecoveryUnavailable() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Profile recovery setup requires completing signup/onboarding again.',
          ),
        ),
      );
  }

  AccountProfileDemoSnapshot _snapshotFromProfile(
    UserProfileReadModel? profile,
    UserProgressReadModel? progress,
    LeaderboardReadModel? leaderboard,
    AccountProfileDemoSnapshot fallback,
    String subscriptionStatusLabel,
  ) {
    if (profile == null) {
      return _snapshotWithProgress(
        fallback,
        progress,
        leaderboard,
        subscriptionStatusLabel,
      );
    }
    return AccountProfileDemoSnapshot(
      displayName: profile.nickname.isEmpty
          ? profile.displayName
          : profile.nickname,
      avatarInitials: profile.avatarInitials,
      avatarUrl: profile.avatarUrl,
      subscriptionStatusLabel: subscriptionStatusLabel,
      regionLabel: profile.locationLabel,
      regionalRankLabel: _accountRegionalRankLabel(leaderboard),
      maxStreakLabel: _accountMaxStreakLabel(progress, fallback),
      totalDistanceLabel: _accountTotalDistanceLabel(progress, fallback),
      divisionKey: _accountDivisionKey(progress, leaderboard),
      divisionLabel: _accountDivisionLabel(progress, leaderboard),
      previewLevelBadge:
          progress?.levelBadgeLabel ??
          (profile.previewLevelBadge.isEmpty
              ? fallback.previewLevelBadge
              : profile.previewLevelBadge),
      levelProgressFraction: progress?.levelProgressFraction ?? 0,
      nextLevelBadge: _nextLevelBadge(progress),
      levelUpCaption: _levelUpCaption(progress),
      levelXpSummary: _levelXpSummary(progress),
      previewNote: profile.previewNote,
      setupSectionLabel: profile.setupSectionLabel.isEmpty
          ? fallback.setupSectionLabel
          : profile.setupSectionLabel,
      manageSectionLabel: profile.manageSectionLabel.isEmpty
          ? fallback.manageSectionLabel
          : profile.manageSectionLabel,
      footerCaption: profile.footerCaption.isEmpty
          ? fallback.footerCaption
          : profile.footerCaption,
      // The note explains the runner's own setup rows, so it must not survive
      // when those rows fall back to the demo snapshot.
      setupNote: profile.setupItems.isEmpty
          ? fallback.setupNote
          : profile.setupNote,
      setupItems: profile.setupItems.isEmpty
          ? fallback.setupItems
          : profile.setupItems
                .map((item) => _setupItemFromProfileItem(item, fallback))
                .toList(growable: false),
      manageRows: profile.manageRows.isEmpty
          ? fallback.manageRows
          : profile.manageRows
                .map((row) => _manageRowFromProfileRow(row, fallback))
                .toList(growable: false),
    );
  }

  AccountProfileDemoSnapshot _snapshotWithProgress(
    AccountProfileDemoSnapshot fallback,
    UserProgressReadModel? progress,
    LeaderboardReadModel? leaderboard,
    String subscriptionStatusLabel,
  ) {
    return AccountProfileDemoSnapshot(
      displayName: fallback.displayName,
      avatarInitials: fallback.avatarInitials,
      avatarUrl: fallback.avatarUrl,
      subscriptionStatusLabel: subscriptionStatusLabel,
      regionLabel: fallback.regionLabel,
      regionalRankLabel: _accountRegionalRankLabel(leaderboard),
      maxStreakLabel: _accountMaxStreakLabel(progress, fallback),
      totalDistanceLabel: _accountTotalDistanceLabel(progress, fallback),
      divisionKey: _accountDivisionKey(progress, leaderboard),
      divisionLabel: _accountDivisionLabel(progress, leaderboard),
      previewLevelBadge:
          progress?.levelBadgeLabel ?? fallback.previewLevelBadge,
      levelProgressFraction: progress?.levelProgressFraction ?? 0,
      nextLevelBadge: _nextLevelBadge(progress),
      levelUpCaption: _levelUpCaption(progress),
      levelXpSummary: _levelXpSummary(progress),
      previewNote: fallback.previewNote,
      setupSectionLabel: fallback.setupSectionLabel,
      manageSectionLabel: fallback.manageSectionLabel,
      footerCaption: fallback.footerCaption,
      setupNote: fallback.setupNote,
      setupItems: fallback.setupItems,
      manageRows: fallback.manageRows,
    );
  }

  // Gauge labels are composed by the shared resolver so this screen and the
  // public runner profile always read identically.
  LevelProgressLabels _levelLabels(UserProgressReadModel? progress) {
    return resolveLevelProgressLabels(
      hasProgress: progress != null,
      level: progress?.level ?? 0,
      isMaxLevel: progress?.isMaxLevel ?? false,
      totalXp: progress?.totalXp,
      nextLevelXp: progress?.nextLevelXp,
      xpToNextLevel: progress?.xpToNextLevel,
    );
  }

  String _nextLevelBadge(UserProgressReadModel? progress) =>
      _levelLabels(progress).nextLevelBadge;

  String _levelUpCaption(UserProgressReadModel? progress) =>
      _levelLabels(progress).levelUpCaption;

  String _levelXpSummary(UserProgressReadModel? progress) =>
      _levelLabels(progress).levelXpSummary;

  /// Trusted, backend-owned regional rank for the current runner in their home
  /// region. The client only relays this label; it never computes rank.
  String _accountRegionalRankLabel(LeaderboardReadModel? leaderboard) {
    if (leaderboard == null ||
        !leaderboard.isHomeRegion ||
        leaderboard.status == LeaderboardReadStatus.unranked) {
      return '';
    }
    return leaderboard.currentRunnerRankLabel.trim();
  }

  /// Relays the backend-owned longest streak; the client never derives it.
  /// When a progress read model is present (real or static repo) its label is
  /// shown as-is, so a real runner with no runs yet renders '—' rather than a
  /// fabricated value. The demo snapshot label only fills in while progress is
  /// still loading (null).
  String _accountMaxStreakLabel(
    UserProgressReadModel? progress,
    AccountProfileDemoSnapshot fallback,
  ) {
    if (progress == null) {
      return fallback.maxStreakLabel;
    }
    return progress.longestStreakLabel.trim();
  }

  /// Relays the backend-owned lifetime distance total; the client never
  /// derives it. Same null-only fallback contract as [_accountMaxStreakLabel].
  String _accountTotalDistanceLabel(
    UserProgressReadModel? progress,
    AccountProfileDemoSnapshot fallback,
  ) {
    if (progress == null) {
      return fallback.totalDistanceLabel;
    }
    return progress.totalDistanceLabel.trim();
  }

  String _accountDivisionKey(
    UserProgressReadModel? progress,
    LeaderboardReadModel? leaderboard,
  ) {
    final progressDivisionKey = progress?.divisionKey.trim() ?? '';
    if (progressDivisionKey.isNotEmpty) {
      return progressDivisionKey;
    }
    if (leaderboard == null ||
        leaderboard.status == LeaderboardReadStatus.unranked) {
      return '';
    }
    return leaderboard.divisionKey;
  }

  String _accountDivisionLabel(
    UserProgressReadModel? progress,
    LeaderboardReadModel? leaderboard,
  ) {
    final progressDivisionKey = progress?.divisionKey.trim() ?? '';
    final progressDivisionLabel = progress?.divisionLabel.trim() ?? '';
    if (progressDivisionKey.isNotEmpty && progressDivisionLabel.isNotEmpty) {
      return progressDivisionLabel;
    }
    if (leaderboard == null ||
        leaderboard.status == LeaderboardReadStatus.unranked) {
      return 'Unranked';
    }
    return leaderboard.divisionLabel;
  }

  AccountProfileInfoItem _setupItemFromProfileItem(
    UserProfileInfoItemReadModel item,
    AccountProfileDemoSnapshot fallback,
  ) {
    return AccountProfileInfoItem(
      icon: _matchingSetupIcon(item.title, fallback),
      title: item.title,
      value: item.value,
    );
  }

  AccountProfileManageRow _manageRowFromProfileRow(
    UserProfileManageRowReadModel row,
    AccountProfileDemoSnapshot fallback,
  ) {
    final matchingFallbackRow = _matchingManageRow(row.title, fallback);
    return AccountProfileManageRow(
      icon: matchingFallbackRow?.icon ?? Icons.settings_outlined,
      title: row.title,
      subtitle: row.subtitle,
      snackBarMessage: row.snackBarMessage,
      action: row.action == UserProfileManageAction.snackBar
          ? matchingFallbackRow?.action ?? UserProfileManageAction.snackBar
          : row.action,
    );
  }

  Future<void> _openEditProfile(UserProfileReadModel profile) async {
    final result = await Navigator.of(context).push<AccountEditProfileResult>(
      MaterialPageRoute<AccountEditProfileResult>(
        builder: (context) => AccountEditProfileScreen(
          authRepository: widget.authRepository,
          persistenceRepository: widget.profilePersistenceRepository,
          generatedPlanPersistenceRepository:
              widget.generatedPlanPersistenceRepository,
          profile: profile,
          onBack: (result) => Navigator.of(context).pop(result),
          avatarUploadGateway: widget.avatarUploadGateway,
          avatarPhotoPicker: widget.avatarPhotoPicker,
        ),
      ),
    );
    if (!mounted || result == null || !result.profileChanged) {
      return;
    }
    setState(() {
      _profileFuture = widget.profileRepository.loadUserProfile();
    });
    if (result.showSuccessOverlay) {
      await showRuniacSuccessCheckOverlay(context, message: 'Profile updated.');
    }
  }

  IconData _matchingSetupIcon(
    String title,
    AccountProfileDemoSnapshot fallback,
  ) {
    for (final item in fallback.setupItems) {
      if (item.title == title) {
        return item.icon;
      }
    }
    return Icons.info_outline;
  }

  AccountProfileManageRow? _matchingManageRow(
    String title,
    AccountProfileDemoSnapshot fallback,
  ) {
    for (final row in fallback.manageRows) {
      if (row.title == title) {
        return row;
      }
    }
    return null;
  }
}

class _EmailVerificationPrompt extends StatelessWidget {
  const _EmailVerificationPrompt({
    required this.email,
    required this.isPending,
    required this.feedbackMessage,
    required this.onResend,
  });

  final String email;
  final bool isPending;
  final String? feedbackMessage;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.sectionSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.mark_email_unread_outlined,
              color: RuniacColors.primaryBlue,
              size: 21,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verify your email',
                    style: TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  if (feedbackMessage != null) ...[
                    const SizedBox(height: 5),
                    Text(
                      feedbackMessage!,
                      style: const TextStyle(
                        color: RuniacColors.primaryBlue,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: isPending ? null : onResend,
              child: Text(isPending ? 'Sending...' : 'Resend email'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountProfileLoadingState extends StatelessWidget {
  const _AccountProfileLoadingState();

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
            'Loading profile...',
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

class _AccountProfileRecoveryState extends StatelessWidget {
  const _AccountProfileRecoveryState({required this.onSetupProfile});

  final VoidCallback onSetupProfile;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RuniacColors.sectionSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: RuniacColors.cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.manage_accounts_outlined,
                  color: RuniacColors.primaryBlue,
                  size: 32,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Profile setup was not found',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Your account is signed in, but the profile setup needed for this page is missing. You can keep using other parts of Runiac while recovery is prepared.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onSetupProfile,
                  child: const Text('Set up profile'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
