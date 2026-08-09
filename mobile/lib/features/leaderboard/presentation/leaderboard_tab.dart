import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../paywall/presentation/premium_gate.dart';
import '../../profile/presentation/runner_public_profile_scope.dart';
import '../../tutorial/domain/models/tutorial_step.dart';
import '../../tutorial/presentation/tutorial_anchor_registry.dart';
import '../data/static_leaderboard_repository.dart';
import '../domain/models/leaderboard_league_catalog.dart';
import '../domain/models/leaderboard_read_model.dart';
import '../domain/repositories/leaderboard_repository.dart';
import 'data/leaderboard_demo_snapshots.dart';
import 'league_asset_path.dart';
import 'leaderboard_read_model_display_adapter.dart';
import 'models/leaderboard_display_models.dart';
import 'widgets/leaderboard_dialogs.dart';
import 'widgets/leaderboard_map_background.dart';
import 'widgets/leaderboard_ranking_screen.dart';
import 'widgets/leaderboard_region_preview_sheet.dart';
import 'widgets/leaderboard_top_overlay.dart';
import 'widgets/runner_achievement_profile_screen.dart';
import 'widgets/share_rank_floating_panel.dart';

/// The Leaderboard tab — the runner's rank within their region and league tier.
///
/// Every number here is server-computed. The client cannot write a leaderboard
/// score (`firestore.rules` rejects it) and does not recompute one for display,
/// so a rank shown here is exactly what the backend ranked.
///
/// [_LeaderboardStateMessage] covers the states this tab spends real time in —
/// loading, empty period, unranked, failed — because a leaderboard that is
/// merely blank gives the runner no idea whether they are unranked or offline.
class LeaderboardTab extends StatefulWidget {
  const LeaderboardTab({
    super.key,
    this.repository = const StaticLeaderboardRepository(),
    this.clock = _systemClock,
  });

  final LeaderboardRepository repository;
  final DateTime Function() clock;

  @override
  State<LeaderboardTab> createState() => _LeaderboardTabState();
}

DateTime _systemClock() => DateTime.timestamp().toLocal();

class _LeaderboardTabState extends State<LeaderboardTab> {
  // The sheet sizes itself to its content and reports the result back, so no
  // constant can describe it: row count, the presence of the My Rank Preview
  // section, message-card line wrapping and the device text scale all move it.
  // These are only the placeholders used for the first frame, before the first
  // measurement lands — the sheet is fully expanded then, so nothing depends
  // on them being exact.
  static const double _userRegionSheetHeightEstimate = 540;
  static const double _regionalSheetHeightEstimate = 425;
  static const double _collapsedSheetHeight = 46;
  static const _expiredRetryDelays = [
    Duration.zero,
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  double _sheetProgress = 1;
  double? _measuredSheetHeight;
  bool _loading = true;
  Object? _loadError;
  LeaderboardReadModel? _readModel;
  LeaderboardDetailDisplaySnapshot? _selectedRegion;
  RunnerAchievementProfileSnapshot? _selectedProfile;
  Timer? _periodRefreshTimer;
  StreamSubscription<LeaderboardReadModel>? _liveUpdateSubscription;
  var _expiredRetryAttempt = 0;
  var _loadSerial = 0;

  @override
  void initState() {
    super.initState();
    _subscribeToLiveUpdates();
    unawaited(_loadLeaderboard());
  }

  @override
  void didUpdateWidget(covariant LeaderboardTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.clock != widget.clock) {
      _expiredRetryAttempt = 0;
      _liveUpdateSubscription?.cancel();
      _subscribeToLiveUpdates();
      unawaited(_loadLeaderboard());
    }
  }

  @override
  void dispose() {
    _periodRefreshTimer?.cancel();
    _liveUpdateSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToLiveUpdates() {
    final repository = widget.repository;
    if (repository is! LiveLeaderboardRepository) {
      return;
    }
    _liveUpdateSubscription = repository.watchLeaderboard().listen(
      (_) => unawaited(_loadLeaderboard()),
      onError: (Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'runiac leaderboard',
            context: ErrorDescription('watching leaderboard updates'),
          ),
        );
      },
    );
  }

  Future<void> _loadLeaderboard() async {
    final loadSerial = ++_loadSerial;
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      final leaderboard = await widget.repository.loadLeaderboard();
      if (!mounted || loadSerial != _loadSerial) {
        return;
      }
      setState(() {
        _readModel = leaderboard;
        _selectedRegion =
            leaderboard.status == LeaderboardReadStatus.regionRequired
            ? null
            : leaderboardDisplaySnapshotFromReadModel(
                leaderboard,
                widget.clock(),
              );
        _loading = false;
      });
      _schedulePeriodRefresh(leaderboard.periodEndsAt);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac leaderboard',
          context: ErrorDescription('loading leaderboard read model'),
        ),
      );
      if (!mounted || loadSerial != _loadSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  Future<void> _selectRegion(String regionId) async {
    final loadSerial = ++_loadSerial;
    setState(() {
      _loading = true;
      _loadError = null;
      _sheetProgress = 1;
    });
    try {
      final leaderboard = await widget.repository.loadRegion(
        regionId: regionId,
      );
      if (!mounted || loadSerial != _loadSerial) {
        return;
      }
      setState(() {
        _readModel = leaderboard;
        _selectedRegion = leaderboardDisplaySnapshotFromReadModel(
          leaderboard,
          widget.clock(),
        );
        _loading = false;
      });
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'runiac leaderboard',
          context: ErrorDescription('loading selected Leaderboard region'),
        ),
      );
      if (!mounted || loadSerial != _loadSerial) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error;
      });
    }
  }

  void _schedulePeriodRefresh(DateTime? periodEndsAt) {
    _periodRefreshTimer?.cancel();
    if (periodEndsAt == null) {
      return;
    }
    final remaining = periodEndsAt.difference(widget.clock());
    if (!remaining.isNegative && remaining > Duration.zero) {
      _expiredRetryAttempt = 0;
      _periodRefreshTimer = Timer(remaining, _loadLeaderboard);
      return;
    }
    if (_expiredRetryAttempt >= _expiredRetryDelays.length) {
      return;
    }
    final delay = _expiredRetryDelays[_expiredRetryAttempt];
    _expiredRetryAttempt += 1;
    if (delay == Duration.zero) {
      scheduleMicrotask(_loadLeaderboard);
    } else {
      _periodRefreshTimer = Timer(delay, _loadLeaderboard);
    }
  }

  void _openRankingPage() {
    final snapshot = _selectedRegion;
    if (snapshot == null) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LeaderboardRankingScreen(snapshot: snapshot),
      ),
    );
  }

  void _openRunnerProfile(RunnerAchievementProfileSnapshot profile) {
    setState(() {
      _selectedProfile = profile;
    });
  }

  void _openShareRankPanel() {
    final snapshot = _selectedRegion;
    if (snapshot == null) {
      return;
    }
    // Rank share-card export: tier owned by config/featureAccess.shareCards.
    // Only the export is gated — the rank itself, and every value behind it,
    // stays identical for Basic and Premium runners.
    if (interceptWithPaywallIfGated(context, 'shareCards')) {
      return;
    }
    // Backend-provided rank when the runner is ranked; otherwise the
    // adapter's presence-derived 'Unranked' summary label. Display-only.
    final currentUserRow = snapshot.nearbyRanks
        .where((row) => row.isCurrentUser)
        .firstOrNull;
    final rankLabel =
        currentUserRow?.rankLabel ?? snapshot.currentUser.rankLabel;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: RuniacColors.textPrimary.withValues(alpha: 0.48),
      builder: (context) {
        return ShareRankFloatingPanel(
          regionName: snapshot.regionName,
          divisionName: snapshot.divisionLabel,
          rankLabel: rankLabel,
          leagueBadgeAssetPath: snapshot.divisionAssetPath,
        );
      },
    );
  }

  void _closeRunnerProfile() {
    setState(() {
      _selectedProfile = null;
    });
  }

  void _handleSheetDragUpdate(DragUpdateDetails details) {
    final expandedSheetHeight = _expandedSheetHeight;
    setState(() {
      _sheetProgress =
          (_sheetProgress -
                  details.delta.dy /
                      (expandedSheetHeight - _collapsedSheetHeight))
              .clamp(0, 1);
    });
  }

  void _handleSheetDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    setState(() {
      if (velocity > 260) {
        _sheetProgress = 0;
      } else if (velocity < -260) {
        _sheetProgress = 1;
      } else {
        _sheetProgress = _sheetProgress >= 0.5 ? 1 : 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedProfile = _selectedProfile;
    if (selectedProfile != null) {
      return RunnerAchievementProfileScreen(
        profile: selectedProfile,
        onBack: _closeRunnerProfile,
        publicProfileRepository: RunnerPublicProfileScope.of(context),
      );
    }
    final snapshot = _selectedRegion;
    final readModel = _readModel;
    // Mutually exclusive early returns: only one of the two branches below can
    // ever execute per build, so wrapping both with the same
    // leaderboardStateMessage anchor id can never mount it twice at once.
    if (readModel?.status == LeaderboardReadStatus.regionRequired) {
      return TutorialAnchor(
        id: TutorialAnchorId.leaderboardStateMessage,
        child: _LeaderboardStateMessage(
          key: const Key('leaderboard_region_required_state'),
          message:
              'Choose your planning area in Profile to join the monthly leaderboard.',
          actionLabel: 'Retry',
          onAction: _loadLeaderboard,
        ),
      );
    }
    if (snapshot == null) {
      return TutorialAnchor(
        id: TutorialAnchorId.leaderboardStateMessage,
        child: _LeaderboardStateMessage(
          key: const Key('leaderboard_initial_state'),
          message: _loadError == null
              ? 'Loading monthly leaderboard…'
              : 'Leaderboard could not be loaded.',
          actionLabel: _loadError == null ? null : 'Retry',
          onAction: _loadError == null ? null : _loadLeaderboard,
          loading: _loading && _loadError == null,
        ),
      );
    }
    final expandedSheetHeight = _expandedSheetHeight;
    final hiddenSheetHeight =
        (expandedSheetHeight - _collapsedSheetHeight) * (1 - _sheetProgress);
    final league =
        leaderboardLeagueForKey(readModel?.divisionKey ?? '') ??
        leaderboardLeagueDefinitions.first;
    final mapRegions = leaderboardMapRegionsForHomeRegion(
      readModel?.homeRegionId ?? '',
    );

    return ColoredBox(
      color: const Color(0xFFEAE6DD),
      child: Stack(
        children: [
          Positioned.fill(
            child: TutorialAnchor(
              id: TutorialAnchorId.leaderboardMap,
              child: LeaderboardMapBackground(
                regions: mapRegions,
                selectedRegionId: snapshot.regionId,
                onRegionSelected: _selectRegion,
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            top: 0,
            child: SafeArea(
              minimum: const EdgeInsets.only(top: 14),
              child: LeaderboardTopOverlay(
                divisionName: league.name,
                levelRange: league.levelRangeLabel,
                assetPath: _leagueAssetPath(league.key),
                onShowLeagues: () => showLeaderboardLeaguesDialog(context),
                onShowTips: () => showLeaderboardTipsDialog(context),
              ),
            ),
          ),
          // Anchored to the full tab area rather than to the sheet's own box:
          // the sheet has no fixed height any more, and this is what hands it
          // the bounded height it caps itself against.
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: 0,
            right: 0,
            top: 0,
            bottom: -hiddenSheetHeight,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: double.infinity,
                child: LeaderboardRegionPreviewSheet(
                  snapshot: snapshot,
                  onVerticalDragUpdate: _handleSheetDragUpdate,
                  onVerticalDragEnd: _handleSheetDragEnd,
                  onViewMoreRanking: _openRankingPage,
                  onShareMyRank: _openShareRankPanel,
                  onProfileSelected: _openRunnerProfile,
                  onHeightMeasured: _handleSheetMeasured,
                  clock: widget.clock,
                ),
              ),
            ),
          ),
          if (_loading)
            const Positioned(
              right: 18,
              top: 84,
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ),
          if (_loadError != null)
            Positioned(
              left: 16,
              right: 16,
              top: 82,
              child: Material(
                color: RuniacColors.white,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  title: const Text('Leaderboard could not be refreshed.'),
                  trailing: TextButton(
                    onPressed: _loadLeaderboard,
                    child: const Text('Retry'),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  double get _expandedSheetHeight {
    return _measuredSheetHeight ??
        (_selectedRegion?.isUserRegion == true
            ? _userRegionSheetHeightEstimate
            : _regionalSheetHeightEstimate);
  }

  void _handleSheetMeasured(double height) {
    if (!mounted || _measuredSheetHeight == height) {
      return;
    }
    setState(() {
      _measuredSheetHeight = height;
    });
  }
}

class _LeaderboardStateMessage extends StatelessWidget {
  const _LeaderboardStateMessage({
    super.key,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: RuniacColors.background,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 18),
              ],
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: RuniacColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 14),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _leagueAssetPath(String key) => leagueAssetPathForTierKey(key);
