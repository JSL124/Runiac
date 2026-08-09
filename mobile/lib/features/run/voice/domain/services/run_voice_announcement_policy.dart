import 'dart:math';

import '../models/run_voice_announcement.dart';
import '../models/run_voice_session_config.dart';
import '../models/run_voice_snapshot.dart';

abstract interface class RunVoiceAnnouncementPolicy {
  RunVoicePolicyResult evaluate({
    required RunVoiceSnapshot previous,
    required RunVoiceSnapshot current,
    required RunVoiceSessionConfig config,
    required Set<String> announcedIds,
  });
}

/// Evaluates distance-milestone, time-interval, and target-distance
/// announcements for a single snapshot transition.
///
/// Each milestone family is evaluated independently and the results are
/// merged into a single [RunVoicePolicyResult]: this method never selects
/// among candidates itself (that is the [RunVoiceAnnouncementSelector]'s
/// job), so more than one announcement may be returned for the same
/// transition (e.g. a distance milestone and a target-completed event
/// crossed by the same GPS jump).
class DefaultRunVoiceAnnouncementPolicy implements RunVoiceAnnouncementPolicy {
  DefaultRunVoiceAnnouncementPolicy({Random? random})
    : _random = random ?? Random();

  final Random _random;

  @override
  RunVoicePolicyResult evaluate({
    required RunVoiceSnapshot previous,
    required RunVoiceSnapshot current,
    required RunVoiceSessionConfig config,
    required Set<String> announcedIds,
  }) {
    if (!config.enabled || !current.isActive || current.isPaused) {
      return const RunVoicePolicyResult.empty();
    }

    final startResult = _evaluateStartEncouragement(
      current: current,
      announcedIds: announcedIds,
    );

    final distanceResult = _evaluateDistanceMilestones(
      previous: previous,
      current: current,
      config: config,
      announcedIds: announcedIds,
    );

    final timeResult = _evaluateTimeMilestones(
      previous: previous,
      current: current,
      config: config,
      announcedIds: announcedIds,
    );

    final targetResult = _evaluateTargetMilestones(
      previous: previous,
      current: current,
      config: config,
      announcedIds: announcedIds,
    );

    final announcements = <RunVoiceAnnouncement>[
      ...startResult.announcements,
      ...distanceResult.announcements,
      ...timeResult.announcements,
      ...targetResult.announcements,
    ];

    if (announcements.isEmpty) {
      return const RunVoicePolicyResult.empty();
    }

    final consumedIds = <String>{
      ...startResult.consumedIds,
      ...distanceResult.consumedIds,
      ...timeResult.consumedIds,
      ...targetResult.consumedIds,
    };

    return RunVoicePolicyResult(
      announcements: announcements,
      consumedIds: consumedIds,
    );
  }

  RunVoicePolicyResult _evaluateStartEncouragement({
    required RunVoiceSnapshot current,
    required Set<String> announcedIds,
  }) {
    if (announcedIds.contains('start') ||
        current.distanceMeters != 0 ||
        current.elapsed != Duration.zero) {
      return const RunVoicePolicyResult.empty();
    }

    final announcement = RunVoiceAnnouncement(
      id: 'start',
      type: RunVoiceAnnouncementType.startEncouragement,
      priority: 10,
      distanceMeters: null,
      elapsed: current.elapsed,
      averagePace: null,
      variant: _random.nextInt(4),
    );

    return RunVoicePolicyResult(
      announcements: [announcement],
      consumedIds: {'start'},
    );
  }

  RunVoicePaceTrend? _paceTrend(RunVoiceSnapshot s) {
    if (s.currentPace == null || s.averagePace == null) {
      return null;
    }
    final c = s.currentPace!.inSeconds;
    final a = s.averagePace!.inSeconds;
    if (a <= 0) {
      return null;
    }
    if (c < a * 0.95) {
      return RunVoicePaceTrend.faster;
    }
    if (c > a * 1.05) {
      return RunVoicePaceTrend.slower;
    }
    return RunVoicePaceTrend.steady;
  }

  RunVoicePolicyResult _evaluateDistanceMilestones({
    required RunVoiceSnapshot previous,
    required RunVoiceSnapshot current,
    required RunVoiceSessionConfig config,
    required Set<String> announcedIds,
  }) {
    final step = config.distanceIntervalMeters;
    if (step <= 0) {
      return const RunVoicePolicyResult.empty();
    }
    if (current.distanceMeters <= previous.distanceMeters) {
      return const RunVoicePolicyResult.empty();
    }

    final crossedIds = <String>{};
    var highestMultiple = 0;
    var multiple = step;
    while (multiple <= current.distanceMeters) {
      if (multiple > previous.distanceMeters) {
        final id = 'distance:$multiple';
        if (!announcedIds.contains(id)) {
          crossedIds.add(id);
          if (multiple > highestMultiple) {
            highestMultiple = multiple;
          }
        }
      }
      multiple += step;
    }

    if (crossedIds.isEmpty) {
      return const RunVoicePolicyResult.empty();
    }

    final announcement = RunVoiceAnnouncement(
      id: 'distance:$highestMultiple',
      type: RunVoiceAnnouncementType.distanceMilestone,
      priority: 50,
      distanceMeters: highestMultiple,
      elapsed: current.elapsed,
      averagePace: current.averagePace,
    );

    return RunVoicePolicyResult(
      announcements: [announcement],
      consumedIds: crossedIds,
    );
  }

  RunVoicePolicyResult _evaluateTimeMilestones({
    required RunVoiceSnapshot previous,
    required RunVoiceSnapshot current,
    required RunVoiceSessionConfig config,
    required Set<String> announcedIds,
  }) {
    final interval = config.timeInterval;
    if (interval == null) {
      return const RunVoicePolicyResult.empty();
    }
    final step = interval.inSeconds;
    if (step <= 0) {
      return const RunVoicePolicyResult.empty();
    }

    final prevSec = previous.elapsed.inSeconds;
    final curSec = current.elapsed.inSeconds;
    if (curSec <= prevSec) {
      return const RunVoicePolicyResult.empty();
    }

    final crossedIds = <String>{};
    var highestMultiple = 0;
    var multiple = step;
    while (multiple <= curSec) {
      if (multiple > prevSec) {
        final id = 'time:$multiple';
        if (!announcedIds.contains(id)) {
          crossedIds.add(id);
          if (multiple > highestMultiple) {
            highestMultiple = multiple;
          }
        }
      }
      multiple += step;
    }

    if (crossedIds.isEmpty) {
      return const RunVoicePolicyResult.empty();
    }

    final announcement = RunVoiceAnnouncement(
      id: 'time:$highestMultiple',
      type: RunVoiceAnnouncementType.timeMilestone,
      priority: 40,
      distanceMeters: null,
      elapsed: Duration(seconds: highestMultiple),
      averagePace: current.averagePace,
    );

    return RunVoicePolicyResult(
      announcements: [announcement],
      consumedIds: crossedIds,
    );
  }

  RunVoicePolicyResult _evaluateTargetMilestones({
    required RunVoiceSnapshot previous,
    required RunVoiceSnapshot current,
    required RunVoiceSessionConfig config,
    required Set<String> announcedIds,
  }) {
    final target = config.targetDistanceMeters;
    if (target == null) {
      return const RunVoicePolicyResult.empty();
    }
    if (current.distanceMeters <= previous.distanceMeters) {
      return const RunVoicePolicyResult.empty();
    }

    final announcements = <RunVoiceAnnouncement>[];
    final consumedIds = <String>{};

    final half = target / 2;
    if (previous.distanceMeters < half &&
        half <= current.distanceMeters &&
        !announcedIds.contains('target:halfway')) {
      consumedIds.add('target:halfway');
      announcements.add(
        RunVoiceAnnouncement(
          id: 'target:halfway',
          type: RunVoiceAnnouncementType.targetHalfway,
          priority: 70,
          distanceMeters: current.distanceMeters,
          elapsed: current.elapsed,
          averagePace: current.averagePace,
          paceTrend: _paceTrend(current),
        ),
      );
    }

    if (previous.distanceMeters < target &&
        target <= current.distanceMeters &&
        !announcedIds.contains('target:completed')) {
      consumedIds.add('target:completed');
      announcements.add(
        RunVoiceAnnouncement(
          id: 'target:completed',
          type: RunVoiceAnnouncementType.targetCompleted,
          priority: 100,
          distanceMeters: current.distanceMeters,
          elapsed: current.elapsed,
          averagePace: current.averagePace,
          paceTrend: _paceTrend(current),
        ),
      );
    }

    if (announcements.isEmpty) {
      return const RunVoicePolicyResult.empty();
    }

    return RunVoicePolicyResult(
      announcements: announcements,
      consumedIds: consumedIds,
    );
  }
}
