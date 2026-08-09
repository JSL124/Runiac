import 'dart:async';

import 'package:flutter/foundation.dart';

/// Injectable wall-clock source. Tests pass a fake that returns controlled
/// instants; production passes `DateTime.now`.
typedef ChallengeClock = DateTime Function();

/// Pure countdown math and formatting for the Challenge deadline.
///
/// Remaining time is always computed as `scheduledEndsAt - now` from an injected
/// clock — never accumulated from ticks — so a paused/resumed screen or a
/// jumped clock always yields the correct value. The formatted label is a
/// fixed-width `DD:HH:MM:SS` string clamped at `00:00:00:00`.
abstract final class ChallengeCountdown {
  static const String zeroLabel = '00:00:00:00';

  /// Fixed-width `HH:MM:SS` zero label for the 24h lobby / invitation windows.
  static const String zeroHmsLabel = '00:00:00';

  /// The non-negative remaining duration between [now] and [scheduledEndsAt].
  /// Past the deadline this clamps to [Duration.zero].
  static Duration remaining({
    required DateTime now,
    required DateTime scheduledEndsAt,
  }) {
    final difference = scheduledEndsAt.difference(now);
    return difference.isNegative ? Duration.zero : difference;
  }

  /// Formats a duration as a fixed-width `DD:HH:MM:SS` label (always at least
  /// two-digit days), clamping negative input to `00:00:00:00`.
  static String format(Duration value) {
    final clamped = value.isNegative ? Duration.zero : value;
    final totalSeconds = clamped.inSeconds;
    final days = totalSeconds ~/ 86400;
    final hours = (totalSeconds % 86400) ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${_two(days)}:${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }

  /// Formats a duration as a fixed-width `HH:MM:SS` label for the 24h lobby /
  /// invitation windows, clamping negative input to `00:00:00`. Hours may
  /// exceed 24 only if a window ever did; within a 24h window it stays 2-digit.
  static String formatHms(Duration value) {
    final clamped = value.isNegative ? Duration.zero : value;
    final totalSeconds = clamped.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    return '${_two(hours)}:${_two(minutes)}:${_two(seconds)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// A 1-second ticker seam. Production uses [PeriodicChallengeTicker]; tests
/// inject a fake that captures the callback so ticks are driven deterministically
/// without real delays.
abstract class ChallengeTicker {
  void start(VoidCallback onTick);
  void stop();
}

class PeriodicChallengeTicker implements ChallengeTicker {
  PeriodicChallengeTicker({this.interval = const Duration(seconds: 1)});

  final Duration interval;
  Timer? _timer;

  @override
  void start(VoidCallback onTick) {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => onTick());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Immutable countdown state exposed to the UI.
@immutable
class ChallengeCountdownValue {
  const ChallengeCountdownValue({
    required this.label,
    required this.remaining,
    required this.isSettling,
    required this.hasSchedule,
  });

  /// Fixed-width `DD:HH:MM:SS` label (or `00:00:00:00` when clamped / absent).
  final String label;
  final Duration remaining;

  /// SETTLING branch signal: the instance is calculating results. The widget
  /// layer renders the canonical "Calculating results…" / "Calculating…" copy;
  /// this module only signals the branch.
  final bool isSettling;

  /// Whether a scheduled deadline is present (an active/settling instance).
  final bool hasSchedule;

  bool get isElapsed => remaining == Duration.zero;

  @override
  bool operator ==(Object other) =>
      other is ChallengeCountdownValue &&
      other.label == label &&
      other.remaining == remaining &&
      other.isSettling == isSettling &&
      other.hasSchedule == hasSchedule;

  @override
  int get hashCode => Object.hash(label, remaining, isSettling, hasSchedule);
}

/// Drives a live countdown from an injected clock and ticker.
///
/// The value is always recomputed from `clock()` vs the server
/// `scheduledEndsAt`; ticks only trigger a recompute, they never accumulate.
/// The controller is disposable and guarantees no tick, recompute, or listener
/// notification occurs after [dispose].
class ChallengeCountdownController extends ChangeNotifier {
  ChallengeCountdownController({
    required this.clock,
    ChallengeTicker? ticker,
    DateTime? scheduledEndsAt,
    bool isSettling = false,
  }) : _ticker = ticker ?? PeriodicChallengeTicker() {
    _scheduledEndsAt = scheduledEndsAt;
    _isSettling = isSettling;
    _value = _compute();
    _syncTicker();
  }

  /// Injected wall-clock source; remaining time is always recomputed from it.
  final ChallengeClock clock;
  final ChallengeTicker _ticker;
  DateTime? _scheduledEndsAt;
  bool _isSettling = false;
  bool _disposed = false;
  late ChallengeCountdownValue _value;

  ChallengeCountdownValue get value => _value;

  bool get _shouldTick =>
      !_disposed &&
      !_isSettling &&
      _scheduledEndsAt != null &&
      _value.remaining > Duration.zero;

  /// Applies a new schedule / settling state (e.g. after refetching the active
  /// challenge) and recomputes immediately.
  void update({DateTime? scheduledEndsAt, bool? isSettling}) {
    if (_disposed) {
      return;
    }
    _scheduledEndsAt = scheduledEndsAt;
    if (isSettling != null) {
      _isSettling = isSettling;
    }
    _refresh();
  }

  /// Recomputes remaining time from the current clock. Call on app resume so a
  /// backgrounded screen re-derives the deadline instead of trusting stale ticks.
  void resume() {
    if (_disposed) {
      return;
    }
    _refresh();
  }

  void _onTick() {
    if (_disposed) {
      return;
    }
    _refresh();
  }

  void _refresh() {
    _value = _compute();
    _syncTicker();
    notifyListeners();
  }

  void _syncTicker() {
    _ticker.stop();
    if (_shouldTick) {
      _ticker.start(_onTick);
    }
  }

  ChallengeCountdownValue _compute() {
    final endsAt = _scheduledEndsAt;
    if (endsAt == null) {
      return ChallengeCountdownValue(
        label: ChallengeCountdown.zeroLabel,
        remaining: Duration.zero,
        isSettling: _isSettling,
        hasSchedule: false,
      );
    }
    final remaining = ChallengeCountdown.remaining(
      now: clock(),
      scheduledEndsAt: endsAt,
    );
    return ChallengeCountdownValue(
      label: ChallengeCountdown.format(remaining),
      remaining: remaining,
      isSettling: _isSettling,
      hasSchedule: true,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.stop();
    super.dispose();
  }
}
