import 'dart:async';

import 'package:flutter/material.dart';

import '../../../challenge/domain/challenge_countdown.dart';

/// Builds the "Refreshes in DD:HH:MM:SS" label from a backend-owned monthly
/// period-end instant. This is a pure display transform of a trusted server
/// timestamp; the client never computes the reset time itself.
String formatLeaderboardRefreshLabel(DateTime? periodEndsAt, DateTime now) {
  if (periodEndsAt == null) {
    return 'Updating';
  }
  final remaining = ChallengeCountdown.remaining(
    now: now,
    scheduledEndsAt: periodEndsAt,
  );
  return 'Refreshes in ${ChallengeCountdown.format(remaining)}';
}

/// Displays the monthly leaderboard refresh countdown.
///
/// When [live] is true and a [periodEndsAt] is present, the label re-derives
/// every second from `clock()` vs the server period end, so the countdown ticks
/// down in real time without ever accumulating from ticks. When [live] is
/// false (a backend-provided static refresh copy) it simply renders
/// [staticLabel]. The internal ticker is cancelled on dispose and stops once
/// the countdown reaches zero.
class LeaderboardRefreshCountdown extends StatefulWidget {
  const LeaderboardRefreshCountdown({
    super.key,
    required this.periodEndsAt,
    required this.staticLabel,
    required this.live,
    required this.style,
    this.clock,
  });

  final DateTime? periodEndsAt;
  final String staticLabel;
  final bool live;
  final TextStyle style;
  final DateTime Function()? clock;

  @override
  State<LeaderboardRefreshCountdown> createState() =>
      _LeaderboardRefreshCountdownState();
}

class _LeaderboardRefreshCountdownState
    extends State<LeaderboardRefreshCountdown> {
  Timer? _ticker;
  late String _label;

  DateTime _now() => (widget.clock ?? _systemClock)();

  bool get _shouldTick =>
      widget.live &&
      widget.periodEndsAt != null &&
      widget.periodEndsAt!.isAfter(_now());

  @override
  void initState() {
    super.initState();
    _syncToWidget();
  }

  @override
  void didUpdateWidget(covariant LeaderboardRefreshCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.periodEndsAt != widget.periodEndsAt ||
        oldWidget.live != widget.live ||
        oldWidget.staticLabel != widget.staticLabel ||
        oldWidget.clock != widget.clock) {
      _syncToWidget();
    }
  }

  void _syncToWidget() {
    _ticker?.cancel();
    _label = _resolveLabel();
    if (_shouldTick) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
    }
  }

  String _resolveLabel() {
    if (!widget.live || widget.periodEndsAt == null) {
      return widget.staticLabel;
    }
    return formatLeaderboardRefreshLabel(widget.periodEndsAt, _now());
  }

  void _onTick() {
    final next = _resolveLabel();
    if (!_shouldTick) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (next != _label && mounted) {
      setState(() => _label = next);
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _label,
      key: const Key('leaderboard_refresh_countdown'),
      style: widget.style,
    );
  }
}

DateTime _systemClock() => DateTime.now();
