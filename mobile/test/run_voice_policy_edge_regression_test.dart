// Regression tests for DefaultRunVoiceAnnouncementPolicy edge cases beyond
// the primary policy suite: guard rails for non-positive intervals, the 500m
// and 2000m distance steps, multi-crossing time jumps, and the target-family
// boundary conditions (halfway + completed in one jump, fractional halves,
// exact boundaries, and the already-at-half no-repeat case).

import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/domain/models/run_voice_announcement.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_snapshot.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_announcement_policy.dart';

RunVoiceSnapshot _snap(
  int distanceMeters, {
  Duration elapsed = Duration.zero,
}) {
  return RunVoiceSnapshot(
    distanceMeters: distanceMeters,
    elapsed: elapsed,
    averagePace: null,
    isActive: true,
    isPaused: false,
  );
}

RunVoiceSessionConfig _config({
  int distanceIntervalMeters = 1000,
  Duration? timeInterval,
  double? targetDistanceMeters,
}) {
  return RunVoiceSessionConfig(
    enabled: true,
    distanceIntervalMeters: distanceIntervalMeters,
    timeInterval: timeInterval,
    includeElapsedTime: true,
    includeAveragePace: true,
    language: RunVoiceLanguage.english,
    targetDistanceMeters: targetDistanceMeters,
  );
}

void main() {
  final policy = DefaultRunVoiceAnnouncementPolicy();

  group('interval guard rails', () {
    test('a zero distance interval announces no distance milestone', () {
      final result = policy.evaluate(
        previous: _snap(100),
        current: _snap(1100),
        config: _config(distanceIntervalMeters: 0),
        announcedIds: {},
      );

      expect(result.announcements, isEmpty);
      expect(result.consumedIds, isEmpty);
    });

    test('a zero-length time interval announces no time milestone', () {
      final result = policy.evaluate(
        previous: _snap(0, elapsed: const Duration(seconds: 10)),
        current: _snap(0, elapsed: const Duration(seconds: 700)),
        config: _config(timeInterval: Duration.zero),
        announcedIds: {},
      );

      expect(result.announcements, isEmpty);
    });
  });

  group('distance step values', () {
    test('a 500m interval announces the 500m milestone', () {
      final result = policy.evaluate(
        previous: _snap(400),
        current: _snap(600),
        config: _config(distanceIntervalMeters: 500),
        announcedIds: {},
      );

      expect(result.announcements.single.id, 'distance:500');
    });

    test(
      'a 2000m interval skips 1km entirely and announces only 2km',
      () {
        final result = policy.evaluate(
          previous: _snap(500),
          current: _snap(2100),
          config: _config(distanceIntervalMeters: 2000),
          announcedIds: {},
        );

        expect(result.announcements.single.id, 'distance:2000');
        expect(result.consumedIds, {'distance:2000'});
        expect(result.consumedIds, isNot(contains('distance:1000')));
      },
    );

    test('landing exactly on a milestone boundary announces it', () {
      final result = policy.evaluate(
        previous: _snap(980),
        current: _snap(1000),
        config: _config(),
        announcedIds: {},
      );

      expect(result.announcements.single.id, 'distance:1000');
    });
  });

  group('time multi-crossing', () {
    test(
      'a jump across three 5-minute intervals announces only the highest '
      'but consumes all crossed ids',
      () {
        final result = policy.evaluate(
          previous: _snap(0, elapsed: const Duration(seconds: 100)),
          current: _snap(0, elapsed: const Duration(seconds: 1000)),
          config: _config(timeInterval: const Duration(minutes: 5)),
          announcedIds: {},
        );

        final timeIds = result.announcements
            .where((a) => a.type == RunVoiceAnnouncementType.timeMilestone)
            .map((a) => a.id)
            .toList();
        expect(timeIds, ['time:900']);
        expect(
          result.consumedIds,
          containsAll(['time:300', 'time:600', 'time:900']),
        );
      },
    );
  });

  group('target boundaries', () {
    test(
      'a tiny target crossed in one jump emits both halfway and completed',
      () {
        final result = policy.evaluate(
          previous: _snap(0),
          current: _snap(200),
          config: _config(distanceIntervalMeters: 5000, targetDistanceMeters: 100),
          announcedIds: {},
        );

        expect(
          result.announcements.map((a) => a.id),
          containsAll(['target:halfway', 'target:completed']),
        );
        expect(
          result.consumedIds,
          containsAll(['target:halfway', 'target:completed']),
        );
      },
    );

    test('a fractional half boundary is crossed correctly', () {
      // target 999 -> half 499.5, crossed by 499 -> 500.
      final result = policy.evaluate(
        previous: _snap(499),
        current: _snap(500),
        config: _config(distanceIntervalMeters: 5000, targetDistanceMeters: 999),
        announcedIds: {},
      );

      expect(
        result.announcements.map((a) => a.id),
        contains('target:halfway'),
      );
      expect(
        result.announcements.where(
          (a) => a.type == RunVoiceAnnouncementType.targetCompleted,
        ),
        isEmpty,
      );
    });

    test('starting exactly at the half boundary does not re-announce halfway', () {
      // previous already at half (500 of a 1000m target): the strict
      // less-than guard must not fire again on the next advance.
      final result = policy.evaluate(
        previous: _snap(500),
        current: _snap(700),
        config: _config(distanceIntervalMeters: 5000, targetDistanceMeters: 1000),
        announcedIds: {},
      );

      expect(
        result.announcements.where(
          (a) => a.type == RunVoiceAnnouncementType.targetHalfway,
        ),
        isEmpty,
      );
    });

    test('landing exactly on the target boundary announces completed', () {
      final result = policy.evaluate(
        previous: _snap(4990),
        current: _snap(5000),
        config: _config(distanceIntervalMeters: 5000, targetDistanceMeters: 5000),
        announcedIds: {'target:halfway'},
      );

      expect(
        result.announcements.map((a) => a.id),
        contains('target:completed'),
      );
    });
  });
}
