import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/challenge_countdown.dart';

class _FakeTicker implements ChallengeTicker {
  VoidCallback? onTick;
  int startCount = 0;
  int stopCount = 0;

  @override
  void start(VoidCallback callback) {
    onTick = callback;
    startCount += 1;
  }

  @override
  void stop() {
    onTick = null;
    stopCount += 1;
  }

  void fire() => onTick?.call();
}

class _MutableClock {
  _MutableClock(this.now);

  DateTime now;

  DateTime call() => now;
}

void main() {
  group('ChallengeCountdown.format', () {
    test('formats multi-day, single-day, and zero durations', () {
      expect(
        ChallengeCountdown.format(
          const Duration(days: 12, hours: 3, minutes: 18, seconds: 42),
        ),
        '12:03:18:42',
      );
      expect(
        ChallengeCountdown.format(
          const Duration(hours: 3, minutes: 18, seconds: 42),
        ),
        '00:03:18:42',
      );
      expect(ChallengeCountdown.format(Duration.zero), '00:00:00:00');
    });

    test('clamps a past deadline to 00:00:00:00', () {
      expect(
        ChallengeCountdown.format(const Duration(seconds: -5)),
        '00:00:00:00',
      );
      final now = DateTime.utc(2026, 7, 13, 12);
      final endsAt = DateTime.utc(2026, 7, 13, 11);
      expect(
        ChallengeCountdown.remaining(now: now, scheduledEndsAt: endsAt),
        Duration.zero,
      );
    });
  });

  group('ChallengeCountdownController', () {
    test('recomputes from the injected clock, never accumulated ticks', () {
      final endsAt = DateTime.utc(2026, 7, 20, 8);
      final clock = _MutableClock(endsAt.subtract(const Duration(seconds: 10)));
      final ticker = _FakeTicker();
      final controller = ChallengeCountdownController(
        clock: clock.call,
        ticker: ticker,
        scheduledEndsAt: endsAt,
      );

      expect(controller.value.remaining, const Duration(seconds: 10));
      expect(controller.value.label, '00:00:00:10');

      // A tick fires after the clock advanced by only 1 second: the recomputed
      // value must reflect the clock, not a fixed decrement schedule.
      clock.now = endsAt.subtract(const Duration(seconds: 9));
      ticker.fire();
      expect(controller.value.remaining, const Duration(seconds: 9));

      controller.dispose();
    });

    test('resume recomputes remaining after a jumped clock', () {
      final endsAt = DateTime.utc(2026, 7, 20, 8);
      final clock = _MutableClock(endsAt.subtract(const Duration(days: 2)));
      final ticker = _FakeTicker();
      final controller = ChallengeCountdownController(
        clock: clock.call,
        ticker: ticker,
        scheduledEndsAt: endsAt,
      );

      expect(controller.value.remaining, const Duration(days: 2));

      clock.now = endsAt.subtract(const Duration(hours: 1));
      controller.resume();
      expect(controller.value.remaining, const Duration(hours: 1));
      expect(controller.value.label, '00:01:00:00');

      controller.dispose();
    });

    test('exposes the SETTLING branch and does not tick while settling', () {
      final clock = _MutableClock(DateTime.utc(2026, 7, 13, 12));
      final ticker = _FakeTicker();
      final controller = ChallengeCountdownController(
        clock: clock.call,
        ticker: ticker,
        scheduledEndsAt: DateTime.utc(2026, 7, 20, 8),
        isSettling: true,
      );

      expect(controller.value.isSettling, isTrue);
      expect(ticker.onTick, isNull);
      expect(ticker.startCount, 0);

      controller.dispose();
    });

    test('does not tick, recompute, or notify after dispose', () {
      final endsAt = DateTime.utc(2026, 7, 20, 8);
      final clock = _MutableClock(endsAt.subtract(const Duration(minutes: 5)));
      final ticker = _FakeTicker();
      final controller = ChallengeCountdownController(
        clock: clock.call,
        ticker: ticker,
        scheduledEndsAt: endsAt,
      );

      var notifications = 0;
      controller.addListener(() => notifications += 1);
      expect(ticker.onTick, isNotNull);
      final capturedTick = ticker.onTick!;
      final valueBeforeDispose = controller.value;

      controller.dispose();
      expect(ticker.stopCount, greaterThanOrEqualTo(1));

      // Invoking the previously-captured tick and requesting a resume after
      // dispose must be inert: no exception, no state change, no notification.
      clock.now = endsAt;
      expect(capturedTick, returnsNormally);
      expect(() => controller.resume(), returnsNormally);
      expect(controller.value, same(valueBeforeDispose));
      expect(notifications, 0);
    });
  });
}
