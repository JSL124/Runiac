// Regression tests for LocalizedRunVoiceMessageFormatter edge cases that the
// primary formatter suite does not exercise: fractional-kilometre wording
// (0.5 / 1.5 / whole-number pluralization), the three duration-formatting
// boundaries (zero, seconds-only, minutes-only, singular), the time-milestone
// pace clause, the documented time-milestone exemption from the elapsed-time
// flag, and the elapsed/pace clauses on the target announcements.

import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/domain/models/run_voice_announcement.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_message_formatter.dart';

RunVoiceAnnouncement _distance(
  int meters, {
  Duration elapsed = const Duration(minutes: 5),
  Duration? averagePace,
}) {
  return RunVoiceAnnouncement(
    id: 'distance:$meters',
    type: RunVoiceAnnouncementType.distanceMilestone,
    priority: 50,
    distanceMeters: meters,
    elapsed: elapsed,
    averagePace: averagePace,
  );
}

RunVoiceAnnouncement _time(
  Duration elapsed, {
  Duration? averagePace,
}) {
  return RunVoiceAnnouncement(
    id: 'time:${elapsed.inSeconds}',
    type: RunVoiceAnnouncementType.timeMilestone,
    priority: 40,
    distanceMeters: null,
    elapsed: elapsed,
    averagePace: averagePace,
  );
}

RunVoiceAnnouncement _targetHalfway({
  Duration elapsed = const Duration(minutes: 5),
  Duration? averagePace,
}) {
  return RunVoiceAnnouncement(
    id: 'target:halfway',
    type: RunVoiceAnnouncementType.targetHalfway,
    priority: 70,
    distanceMeters: 2500,
    elapsed: elapsed,
    averagePace: averagePace,
  );
}

RunVoiceAnnouncement _targetCompleted({
  Duration elapsed = const Duration(minutes: 5),
  Duration? averagePace,
}) {
  return RunVoiceAnnouncement(
    id: 'target:completed',
    type: RunVoiceAnnouncementType.targetCompleted,
    priority: 100,
    distanceMeters: 5000,
    elapsed: elapsed,
    averagePace: averagePace,
  );
}

RunVoiceSessionConfig _config(
  RunVoiceLanguage language, {
  bool includeElapsedTime = false,
  bool includeAveragePace = false,
}) {
  return RunVoiceSessionConfig(
    enabled: true,
    distanceIntervalMeters: 500,
    timeInterval: null,
    includeElapsedTime: includeElapsedTime,
    includeAveragePace: includeAveragePace,
    language: language,
    targetDistanceMeters: null,
  );
}

void main() {
  const formatter = LocalizedRunVoiceMessageFormatter();

  group('fractional and whole kilometre wording', () {
    test('500m reads 0.5 kilometers (plural) in English', () {
      expect(
        formatter.format(_distance(500), _config(RunVoiceLanguage.english)),
        'You have completed 0.5 kilometers.',
      );
    });

    test('1500m reads 1.5 kilometers (plural) in English', () {
      expect(
        formatter.format(_distance(1500), _config(RunVoiceLanguage.english)),
        'You have completed 1.5 kilometers.',
      );
    });

    test('2000m reads a whole 2 kilometers (plural) in English', () {
      expect(
        formatter.format(_distance(2000), _config(RunVoiceLanguage.english)),
        'You have completed 2 kilometers.',
      );
    });

    test('500m localizes to 0.5 in Korean and Chinese', () {
      expect(
        formatter.format(_distance(500), _config(RunVoiceLanguage.korean)),
        '0.5킬로미터를 완료했습니다.',
      );
      expect(
        formatter.format(
          _distance(500),
          _config(RunVoiceLanguage.simplifiedChinese),
        ),
        '您已完成0.5公里。',
      );
    });
  });

  group('duration formatting boundaries (via the elapsed-time clause)', () {
    test('a zero elapsed duration reads as 0 seconds in each language', () {
      expect(
        formatter.format(
          _distance(1000, elapsed: Duration.zero),
          _config(RunVoiceLanguage.english, includeElapsedTime: true),
        ),
        'You have completed 1 kilometer. Your time is 0 seconds.',
      );
      expect(
        formatter.format(
          _distance(1000, elapsed: Duration.zero),
          _config(RunVoiceLanguage.korean, includeElapsedTime: true),
        ),
        '1킬로미터를 완료했습니다. 운동 시간은 0초입니다.',
      );
      expect(
        formatter.format(
          _distance(1000, elapsed: Duration.zero),
          _config(RunVoiceLanguage.simplifiedChinese, includeElapsedTime: true),
        ),
        '您已完成1公里。运动时间0秒。',
      );
    });

    test('a seconds-only duration omits the minutes component', () {
      expect(
        formatter.format(
          _distance(1000, elapsed: const Duration(seconds: 45)),
          _config(RunVoiceLanguage.english, includeElapsedTime: true),
        ),
        'You have completed 1 kilometer. Your time is 45 seconds.',
      );
      expect(
        formatter.format(
          _distance(1000, elapsed: const Duration(seconds: 45)),
          _config(RunVoiceLanguage.korean, includeElapsedTime: true),
        ),
        '1킬로미터를 완료했습니다. 운동 시간은 45초입니다.',
      );
    });

    test('a whole-minute duration omits the seconds component', () {
      expect(
        formatter.format(
          _distance(1000, elapsed: const Duration(minutes: 6)),
          _config(RunVoiceLanguage.english, includeElapsedTime: true),
        ),
        'You have completed 1 kilometer. Your time is 6 minutes.',
      );
      expect(
        formatter.format(
          _distance(1000, elapsed: const Duration(minutes: 6)),
          _config(RunVoiceLanguage.simplifiedChinese, includeElapsedTime: true),
        ),
        '您已完成1公里。运动时间6分。',
      );
    });

    test('English singularizes a one-minute-one-second duration', () {
      expect(
        formatter.format(
          _distance(1000, elapsed: const Duration(minutes: 1, seconds: 1)),
          _config(RunVoiceLanguage.english, includeElapsedTime: true),
        ),
        'You have completed 1 kilometer. Your time is 1 minute 1 second.',
      );
    });
  });

  group('time milestone', () {
    test('states the average pace clause when a pace is available', () {
      expect(
        formatter.format(
          _time(
            const Duration(seconds: 600),
            averagePace: const Duration(minutes: 6),
          ),
          _config(RunVoiceLanguage.english, includeAveragePace: true),
        ),
        '10 minutes elapsed. Your average pace is 6 minutes per kilometer.',
      );
    });

    test(
      'is exempt from includeElapsedTime: it never appends a second time clause',
      () {
        final message = formatter.format(
          _time(const Duration(seconds: 600)),
          _config(RunVoiceLanguage.english, includeElapsedTime: true),
        );

        expect(message, '10 minutes elapsed.');
        expect(message, isNot(contains('Your time is')));
      },
    );
  });

  group('target announcements with elapsed + pace clauses', () {
    test('target halfway appends both clauses in English', () {
      expect(
        formatter.format(
          _targetHalfway(
            elapsed: const Duration(minutes: 12, seconds: 30),
            averagePace: const Duration(minutes: 5),
          ),
          _config(
            RunVoiceLanguage.english,
            includeElapsedTime: true,
            includeAveragePace: true,
          ),
        ),
        'You are halfway to your goal. Your time is 12 minutes 30 seconds. '
        'Your average pace is 5 minutes per kilometer.',
      );
    });

    test(
      'target completed always appends the analysis clause in Korean '
      '(not gated by include flags)',
      () {
        expect(
          formatter.format(
            _targetCompleted(
              elapsed: const Duration(minutes: 30),
              averagePace: const Duration(minutes: 6, seconds: 5),
            ),
            _config(
              RunVoiceLanguage.korean,
              includeElapsedTime: true,
              includeAveragePace: true,
            ),
          ),
          '목표 거리를 완료했습니다. 수고하셨습니다. 총 5킬로미터를 30분에 완주했고, '
          '평균 페이스는 킬로미터당 6분 5초입니다.',
        );
      },
    );
  });
}
