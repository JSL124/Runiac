import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/domain/models/run_voice_announcement.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_snapshot.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_announcement_policy.dart';

RunVoiceSnapshot _snapshot(
  int distanceMeters, {
  bool isActive = true,
  bool isPaused = false,
  Duration elapsed = Duration.zero,
  Duration? averagePace,
  Duration? currentPace,
}) {
  return RunVoiceSnapshot(
    distanceMeters: distanceMeters,
    elapsed: elapsed,
    averagePace: averagePace,
    isActive: isActive,
    isPaused: isPaused,
    currentPace: currentPace,
  );
}

RunVoiceSessionConfig _config({
  bool enabled = true,
  int distanceIntervalMeters = 1000,
  Duration? timeInterval,
  double? targetDistanceMeters,
}) {
  return RunVoiceSessionConfig(
    enabled: enabled,
    distanceIntervalMeters: distanceIntervalMeters,
    timeInterval: timeInterval,
    includeElapsedTime: true,
    includeAveragePace: true,
    language: RunVoiceLanguage.english,
    targetDistanceMeters: targetDistanceMeters,
  );
}

void main() {
  group('DefaultRunVoiceAnnouncementPolicy', () {
    final policy = DefaultRunVoiceAnnouncementPolicy();

    test('crossing a single 1000m milestone announces exactly once', () {
      final result = policy.evaluate(
        previous: _snapshot(980),
        current: _snapshot(1020),
        config: _config(),
        announcedIds: {},
      );

      expect(result.announcements, hasLength(1));
      expect(result.announcements.single.id, 'distance:1000');
      expect(result.consumedIds, {'distance:1000'});
    });

    test('staying below the first milestone announces nothing', () {
      final result = policy.evaluate(
        previous: _snapshot(800),
        current: _snapshot(999),
        config: _config(),
        announcedIds: {},
      );

      expect(result.announcements, isEmpty);
      expect(result.consumedIds, isEmpty);
    });

    test('crossing the milestone from fractional-rounded meters announces', () {
      final result = policy.evaluate(
        previous: _snapshot(998),
        current: _snapshot(1008),
        config: _config(),
        announcedIds: {},
      );

      expect(result.announcements, hasLength(1));
      expect(result.announcements.single.id, 'distance:1000');
    });

    test('an already-announced milestone is not re-announced', () {
      final result = policy.evaluate(
        previous: _snapshot(1005),
        current: _snapshot(1100),
        config: _config(),
        announcedIds: {'distance:1000'},
      );

      expect(result.announcements, isEmpty);
      expect(result.consumedIds, isEmpty);
    });

    test('a distance decrease announces nothing', () {
      final result = policy.evaluate(
        previous: _snapshot(1010),
        current: _snapshot(990),
        config: _config(),
        announcedIds: {},
      );

      expect(result.announcements, isEmpty);
      expect(result.consumedIds, isEmpty);
    });

    test(
      'a GPS jump across multiple milestones announces only the highest '
      'but consumes all crossed ids',
      () {
        final result = policy.evaluate(
          previous: _snapshot(900),
          current: _snapshot(2100),
          config: _config(),
          announcedIds: {},
        );

        expect(result.announcements, hasLength(1));
        expect(result.announcements.single.id, 'distance:2000');
        expect(result.consumedIds, {'distance:1000', 'distance:2000'});
      },
    );

    test('a disabled config announces nothing', () {
      final result = policy.evaluate(
        previous: _snapshot(980),
        current: _snapshot(1020),
        config: _config(enabled: false),
        announcedIds: {},
      );

      expect(result.announcements, isEmpty);
      expect(result.consumedIds, isEmpty);
    });

    test('a paused snapshot announces nothing', () {
      final result = policy.evaluate(
        previous: _snapshot(980),
        current: _snapshot(1020, isPaused: true),
        config: _config(),
        announcedIds: {},
      );

      expect(result.announcements, isEmpty);
      expect(result.consumedIds, isEmpty);
    });

    test('an inactive snapshot announces nothing', () {
      final result = policy.evaluate(
        previous: _snapshot(980),
        current: _snapshot(1020, isActive: false),
        config: _config(),
        announcedIds: {},
      );

      expect(result.announcements, isEmpty);
      expect(result.consumedIds, isEmpty);
    });

    test('crossing a 10-minute time interval announces exactly once', () {
      final result = policy.evaluate(
        previous: _snapshot(0, elapsed: const Duration(minutes: 9, seconds: 58)),
        current: _snapshot(0, elapsed: const Duration(minutes: 10, seconds: 2)),
        config: _config(timeInterval: const Duration(minutes: 10)),
        announcedIds: {},
      );

      expect(
        result.announcements.map((a) => a.id),
        contains('time:600'),
      );
      expect(result.consumedIds, contains('time:600'));
    });

    test('a null timeInterval never announces a time milestone', () {
      final result = policy.evaluate(
        previous: _snapshot(0, elapsed: const Duration(minutes: 9, seconds: 58)),
        current: _snapshot(0, elapsed: const Duration(minutes: 10, seconds: 2)),
        config: _config(),
        announcedIds: {},
      );

      expect(
        result.announcements.where(
          (a) => a.type == RunVoiceAnnouncementType.timeMilestone,
        ),
        isEmpty,
      );
    });

    test('an already-announced time milestone is not re-announced', () {
      final result = policy.evaluate(
        previous: _snapshot(0, elapsed: const Duration(minutes: 9, seconds: 58)),
        current: _snapshot(0, elapsed: const Duration(minutes: 10, seconds: 2)),
        config: _config(timeInterval: const Duration(minutes: 10)),
        announcedIds: {'time:600'},
      );

      expect(
        result.announcements.where(
          (a) => a.type == RunVoiceAnnouncementType.timeMilestone,
        ),
        isEmpty,
      );
    });

    test('crossing target halfway (5000m target) announces target:halfway', () {
      final result = policy.evaluate(
        previous: _snapshot(2400),
        current: _snapshot(2550),
        config: _config(targetDistanceMeters: 5000),
        announcedIds: {},
      );

      expect(
        result.announcements.map((a) => a.id),
        contains('target:halfway'),
      );
      expect(result.consumedIds, contains('target:halfway'));
    });

    test('a free run (no target) never announces target:halfway', () {
      final result = policy.evaluate(
        previous: _snapshot(2400),
        current: _snapshot(2550),
        config: _config(),
        announcedIds: {},
      );

      expect(
        result.announcements.where(
          (a) => a.type == RunVoiceAnnouncementType.targetHalfway,
        ),
        isEmpty,
      );
    });

    test(
      'crossing the target distance (5000m target) announces target:completed',
      () {
        final result = policy.evaluate(
          previous: _snapshot(4950),
          current: _snapshot(5030),
          config: _config(targetDistanceMeters: 5000),
          announcedIds: {'target:halfway'},
        );

        expect(
          result.announcements.map((a) => a.id),
          contains('target:completed'),
        );
        expect(result.consumedIds, contains('target:completed'));
      },
    );

    test(
      'a distance milestone and target:completed crossed by the same jump '
      'both appear in announcements',
      () {
        final result = policy.evaluate(
          previous: _snapshot(4950),
          current: _snapshot(5030),
          config: _config(targetDistanceMeters: 5000),
          announcedIds: {'target:halfway'},
        );

        expect(
          result.announcements.map((a) => a.id),
          containsAll(['distance:5000', 'target:completed']),
        );
      },
    );
  });

  group('DefaultRunVoiceAnnouncementPolicy start encouragement', () {
    test(
      'the genuine first snapshot (distance 0, elapsed 0, active) fires '
      'a startEncouragement announcement',
      () {
        final policy = DefaultRunVoiceAnnouncementPolicy();
        final zeroSnap = _snapshot(0, elapsed: Duration.zero);

        final result = policy.evaluate(
          previous: zeroSnap,
          current: zeroSnap,
          config: _config(),
          announcedIds: {},
        );

        expect(
          result.announcements,
          contains(
            predicate<RunVoiceAnnouncement>(
              (a) =>
                  a.id == 'start' &&
                  a.type == RunVoiceAnnouncementType.startEncouragement,
            ),
          ),
        );
        expect(result.consumedIds, contains('start'));
      },
    );

    test('the emitted variant matches the seeded Random source', () {
      final policy = DefaultRunVoiceAnnouncementPolicy(random: Random(1));
      final zeroSnap = _snapshot(0, elapsed: Duration.zero);
      final expectedVariant = Random(1).nextInt(4);

      final result = policy.evaluate(
        previous: zeroSnap,
        current: zeroSnap,
        config: _config(),
        announcedIds: {},
      );

      final start = result.announcements.firstWhere((a) => a.id == 'start');
      expect(start.variant, expectedVariant);
    });

    test('start does not fire when distance is already above 0', () {
      final policy = DefaultRunVoiceAnnouncementPolicy();
      final result = policy.evaluate(
        previous: _snapshot(10, elapsed: Duration.zero),
        current: _snapshot(10, elapsed: Duration.zero),
        config: _config(),
        announcedIds: {},
      );

      expect(
        result.announcements.where(
          (a) => a.type == RunVoiceAnnouncementType.startEncouragement,
        ),
        isEmpty,
      );
    });

    test('start does not fire when elapsed is already above zero', () {
      final policy = DefaultRunVoiceAnnouncementPolicy();
      final result = policy.evaluate(
        previous: _snapshot(0, elapsed: const Duration(seconds: 5)),
        current: _snapshot(0, elapsed: const Duration(seconds: 5)),
        config: _config(),
        announcedIds: {},
      );

      expect(
        result.announcements.where(
          (a) => a.type == RunVoiceAnnouncementType.startEncouragement,
        ),
        isEmpty,
      );
    });

    test('start does not fire twice once already announced', () {
      final policy = DefaultRunVoiceAnnouncementPolicy();
      final zeroSnap = _snapshot(0, elapsed: Duration.zero);
      final result = policy.evaluate(
        previous: zeroSnap,
        current: zeroSnap,
        config: _config(),
        announcedIds: {'start'},
      );

      expect(
        result.announcements.where(
          (a) => a.type == RunVoiceAnnouncementType.startEncouragement,
        ),
        isEmpty,
      );
    });
  });

  group('DefaultRunVoiceAnnouncementPolicy paceTrend', () {
    final policy = DefaultRunVoiceAnnouncementPolicy();
    const averagePace = Duration(seconds: 300);

    test('halfway announcement carries faster paceTrend', () {
      final result = policy.evaluate(
        previous: _snapshot(2400),
        current: _snapshot(
          2550,
          averagePace: averagePace,
          currentPace: const Duration(seconds: 250),
        ),
        config: _config(targetDistanceMeters: 5000),
        announcedIds: {},
      );

      final halfway = result.announcements.firstWhere(
        (a) => a.id == 'target:halfway',
      );
      expect(halfway.paceTrend, RunVoicePaceTrend.faster);
    });

    test('halfway announcement carries steady paceTrend', () {
      final result = policy.evaluate(
        previous: _snapshot(2400),
        current: _snapshot(
          2550,
          averagePace: averagePace,
          currentPace: const Duration(seconds: 300),
        ),
        config: _config(targetDistanceMeters: 5000),
        announcedIds: {},
      );

      final halfway = result.announcements.firstWhere(
        (a) => a.id == 'target:halfway',
      );
      expect(halfway.paceTrend, RunVoicePaceTrend.steady);
    });

    test('halfway announcement carries slower paceTrend', () {
      final result = policy.evaluate(
        previous: _snapshot(2400),
        current: _snapshot(
          2550,
          averagePace: averagePace,
          currentPace: const Duration(seconds: 350),
        ),
        config: _config(targetDistanceMeters: 5000),
        announcedIds: {},
      );

      final halfway = result.announcements.firstWhere(
        (a) => a.id == 'target:halfway',
      );
      expect(halfway.paceTrend, RunVoicePaceTrend.slower);
    });

    test(
      'halfway announcement paceTrend is null when currentPace is null',
      () {
        final result = policy.evaluate(
          previous: _snapshot(2400),
          current: _snapshot(2550, averagePace: averagePace),
          config: _config(targetDistanceMeters: 5000),
          announcedIds: {},
        );

        final halfway = result.announcements.firstWhere(
          (a) => a.id == 'target:halfway',
        );
        expect(halfway.paceTrend, isNull);
      },
    );

    test(
      'halfway announcement paceTrend is null when averagePace is null',
      () {
        final result = policy.evaluate(
          previous: _snapshot(2400),
          current: _snapshot(
            2550,
            currentPace: const Duration(seconds: 250),
          ),
          config: _config(targetDistanceMeters: 5000),
          announcedIds: {},
        );

        final halfway = result.announcements.firstWhere(
          (a) => a.id == 'target:halfway',
        );
        expect(halfway.paceTrend, isNull);
      },
    );

    test('completed announcement carries faster paceTrend', () {
      final result = policy.evaluate(
        previous: _snapshot(4950),
        current: _snapshot(
          5030,
          averagePace: averagePace,
          currentPace: const Duration(seconds: 250),
        ),
        config: _config(targetDistanceMeters: 5000),
        announcedIds: {'target:halfway'},
      );

      final completed = result.announcements.firstWhere(
        (a) => a.id == 'target:completed',
      );
      expect(completed.paceTrend, RunVoicePaceTrend.faster);
    });

    test('completed announcement carries steady paceTrend', () {
      final result = policy.evaluate(
        previous: _snapshot(4950),
        current: _snapshot(
          5030,
          averagePace: averagePace,
          currentPace: const Duration(seconds: 300),
        ),
        config: _config(targetDistanceMeters: 5000),
        announcedIds: {'target:halfway'},
      );

      final completed = result.announcements.firstWhere(
        (a) => a.id == 'target:completed',
      );
      expect(completed.paceTrend, RunVoicePaceTrend.steady);
    });

    test('completed announcement carries slower paceTrend', () {
      final result = policy.evaluate(
        previous: _snapshot(4950),
        current: _snapshot(
          5030,
          averagePace: averagePace,
          currentPace: const Duration(seconds: 350),
        ),
        config: _config(targetDistanceMeters: 5000),
        announcedIds: {'target:halfway'},
      );

      final completed = result.announcements.firstWhere(
        (a) => a.id == 'target:completed',
      );
      expect(completed.paceTrend, RunVoicePaceTrend.slower);
    });

    test(
      'completed announcement paceTrend is null when currentPace is null',
      () {
        final result = policy.evaluate(
          previous: _snapshot(4950),
          current: _snapshot(5030, averagePace: averagePace),
          config: _config(targetDistanceMeters: 5000),
          announcedIds: {'target:halfway'},
        );

        final completed = result.announcements.firstWhere(
          (a) => a.id == 'target:completed',
        );
        expect(completed.paceTrend, isNull);
      },
    );

    test(
      'completed announcement paceTrend is null when averagePace is null',
      () {
        final result = policy.evaluate(
          previous: _snapshot(4950),
          current: _snapshot(
            5030,
            currentPace: const Duration(seconds: 250),
          ),
          config: _config(targetDistanceMeters: 5000),
          announcedIds: {'target:halfway'},
        );

        final completed = result.announcements.firstWhere(
          (a) => a.id == 'target:completed',
        );
        expect(completed.paceTrend, isNull);
      },
    );
  });
}
