import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/domain/models/run_voice_announcement.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_language.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_message_formatter.dart';

RunVoiceAnnouncement _startEncouragement({int? variant}) {
  return RunVoiceAnnouncement(
    id: 'start',
    type: RunVoiceAnnouncementType.startEncouragement,
    priority: 10,
    distanceMeters: null,
    elapsed: Duration.zero,
    averagePace: null,
    variant: variant,
  );
}

RunVoiceAnnouncement _milestone(
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

RunVoiceAnnouncement _timeMilestone(
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
  RunVoicePaceTrend? paceTrend,
}) {
  return RunVoiceAnnouncement(
    id: 'target:halfway',
    type: RunVoiceAnnouncementType.targetHalfway,
    priority: 70,
    distanceMeters: 2500,
    elapsed: elapsed,
    averagePace: averagePace,
    paceTrend: paceTrend,
  );
}

RunVoiceAnnouncement _targetCompleted({
  Duration elapsed = const Duration(minutes: 5),
  int distanceMeters = 5000,
  Duration? averagePace,
  RunVoicePaceTrend? paceTrend,
}) {
  return RunVoiceAnnouncement(
    id: 'target:completed',
    type: RunVoiceAnnouncementType.targetCompleted,
    priority: 100,
    distanceMeters: distanceMeters,
    elapsed: elapsed,
    averagePace: averagePace,
    paceTrend: paceTrend,
  );
}

RunVoiceSessionConfig _config(
  RunVoiceLanguage language, {
  bool includeElapsedTime = false,
  bool includeAveragePace = false,
}) {
  return RunVoiceSessionConfig(
    enabled: true,
    distanceIntervalMeters: 1000,
    timeInterval: null,
    includeElapsedTime: includeElapsedTime,
    includeAveragePace: includeAveragePace,
    language: language,
    targetDistanceMeters: null,
  );
}

void main() {
  group('LocalizedRunVoiceMessageFormatter', () {
    const formatter = LocalizedRunVoiceMessageFormatter();

    group('start encouragement', () {
      test('a null variant defaults to English pool index 0', () {
        final message = formatter.format(
          _startEncouragement(),
          _config(RunVoiceLanguage.english),
        );
        expect(message, "Let's start your run. You've got this!");
      });

      test('English variant pool selects by variant % 4', () {
        const expected = <String>[
          "Let's start your run. You've got this!",
          'Time to run. Enjoy every step!',
          'Starting now — steady and strong!',
          'Here we go. Have a great run!',
        ];
        for (var i = 0; i < expected.length; i++) {
          final message = formatter.format(
            _startEncouragement(variant: i),
            _config(RunVoiceLanguage.english),
          );
          expect(message, expected[i], reason: 'variant $i');
        }
      });

      test('Korean variant pool selects by variant % 4', () {
        const expected = <String>[
          '러닝을 시작합니다. 오늘도 힘내세요!',
          '천천히, 꾸준히. 시작합니다!',
          '오늘의 러닝을 시작합니다. 즐겁게 달려요!',
          '좋은 페이스로 시작해볼까요? 화이팅!',
        ];
        for (var i = 0; i < expected.length; i++) {
          final message = formatter.format(
            _startEncouragement(variant: i),
            _config(RunVoiceLanguage.korean),
          );
          expect(message, expected[i], reason: 'variant $i');
        }
      });

      test('Simplified Chinese variant pool selects by variant % 4', () {
        const expected = <String>[
          '开始跑步。今天也加油！',
          '慢慢来，坚持住。开始吧！',
          '开始今天的跑步。享受每一步！',
          '让我们出发吧，跑个痛快！',
        ];
        for (var i = 0; i < expected.length; i++) {
          final message = formatter.format(
            _startEncouragement(variant: i),
            _config(RunVoiceLanguage.simplifiedChinese),
          );
          expect(message, expected[i], reason: 'variant $i');
        }
      });

      test('variant wraps around with modulo 4', () {
        final message = formatter.format(
          _startEncouragement(variant: 5),
          _config(RunVoiceLanguage.english),
        );
        expect(message, 'Time to run. Enjoy every step!');
      });
    });

    group('distance milestone (flags off, bare line)', () {
      test('formats the 1km distance milestone in English', () {
        final message = formatter.format(
          _milestone(1000),
          _config(RunVoiceLanguage.english),
        );
        expect(message, 'You have completed 1 kilometer.');
      });

      test('formats the 1km distance milestone in Korean', () {
        final message = formatter.format(
          _milestone(1000),
          _config(RunVoiceLanguage.korean),
        );
        expect(message, '1킬로미터를 완료했습니다.');
      });

      test('formats the 1km distance milestone in Simplified Chinese', () {
        final message = formatter.format(
          _milestone(1000),
          _config(RunVoiceLanguage.simplifiedChinese),
        );
        expect(message, '您已完成1公里。');
      });
    });

    group('distance milestone (elapsed + pace clauses)', () {
      test('English: elapsed 6:12, pace 6:12', () {
        final message = formatter.format(
          _milestone(
            1000,
            elapsed: const Duration(minutes: 6, seconds: 12),
            averagePace: const Duration(minutes: 6, seconds: 12),
          ),
          _config(
            RunVoiceLanguage.english,
            includeElapsedTime: true,
            includeAveragePace: true,
          ),
        );
        expect(
          message,
          'You have completed 1 kilometer. Your time is 6 minutes 12 '
          'seconds. Your average pace is 6 minutes 12 seconds per '
          'kilometer.',
        );
      });

      test('Korean: elapsed 6:12, pace 6:12', () {
        final message = formatter.format(
          _milestone(
            1000,
            elapsed: const Duration(minutes: 6, seconds: 12),
            averagePace: const Duration(minutes: 6, seconds: 12),
          ),
          _config(
            RunVoiceLanguage.korean,
            includeElapsedTime: true,
            includeAveragePace: true,
          ),
        );
        expect(
          message,
          '1킬로미터를 완료했습니다. 운동 시간은 6분 12초입니다. 평균 페이스는 킬로미터당 6분 12초입니다.',
        );
      });

      test('Simplified Chinese: elapsed 6:12, pace 6:12', () {
        final message = formatter.format(
          _milestone(
            1000,
            elapsed: const Duration(minutes: 6, seconds: 12),
            averagePace: const Duration(minutes: 6, seconds: 12),
          ),
          _config(
            RunVoiceLanguage.simplifiedChinese,
            includeElapsedTime: true,
            includeAveragePace: true,
          ),
        );
        expect(message, '您已完成1公里。运动时间6分12秒。平均配速每公里6分12秒。');
      });

      test('a null averagePace omits the pace clause even when enabled', () {
        final message = formatter.format(
          _milestone(
            1000,
            elapsed: const Duration(minutes: 6, seconds: 12),
          ),
          _config(
            RunVoiceLanguage.english,
            includeElapsedTime: true,
            includeAveragePace: true,
          ),
        );
        expect(
          message,
          'You have completed 1 kilometer. Your time is 6 minutes 12 '
          'seconds.',
        );
      });

      test('includeAveragePace false omits the pace clause', () {
        final message = formatter.format(
          _milestone(
            1000,
            elapsed: const Duration(minutes: 6, seconds: 12),
            averagePace: const Duration(minutes: 6, seconds: 12),
          ),
          _config(
            RunVoiceLanguage.english,
            includeElapsedTime: true,
          ),
        );
        expect(
          message,
          'You have completed 1 kilometer. Your time is 6 minutes 12 '
          'seconds.',
        );
      });
    });

    group('time milestone', () {
      test('10 minutes elapsed, Korean, no pace', () {
        final message = formatter.format(
          _timeMilestone(const Duration(seconds: 600)),
          _config(RunVoiceLanguage.korean),
        );
        expect(message, '10분 경과했습니다.');
      });

      test('10 minutes elapsed, English, no pace', () {
        final message = formatter.format(
          _timeMilestone(const Duration(seconds: 600)),
          _config(RunVoiceLanguage.english),
        );
        expect(message, '10 minutes elapsed.');
      });

      test('10 minutes elapsed, Simplified Chinese, no pace', () {
        final message = formatter.format(
          _timeMilestone(const Duration(seconds: 600)),
          _config(RunVoiceLanguage.simplifiedChinese),
        );
        expect(message, '已经过10分钟。');
      });
    });

    group('target halfway', () {
      test('English base line (paceTrend null omits the eval clause)', () {
        final message = formatter.format(
          _targetHalfway(),
          _config(RunVoiceLanguage.english),
        );
        expect(message, 'You are halfway to your goal.');
      });

      test('Korean base line (paceTrend null omits the eval clause)', () {
        final message = formatter.format(
          _targetHalfway(),
          _config(RunVoiceLanguage.korean),
        );
        expect(message, '목표 거리의 절반을 지났습니다.');
      });

      test(
        'Simplified Chinese base line (paceTrend null omits the eval '
        'clause)',
        () {
          final message = formatter.format(
            _targetHalfway(),
            _config(RunVoiceLanguage.simplifiedChinese),
          );
          expect(message, '您已到达目标距离的一半。');
        },
      );

      test('English: faster pace trend appends the eval clause', () {
        final message = formatter.format(
          _targetHalfway(paceTrend: RunVoicePaceTrend.faster),
          _config(RunVoiceLanguage.english),
        );
        expect(
          message,
          'You are halfway to your goal. Your pace is picking up — keep '
          'it going!',
        );
      });

      test(
        'Korean: steady pace trend + elapsed 15:30 + pace 6:12 with both '
        'flags on',
        () {
          final message = formatter.format(
            _targetHalfway(
              elapsed: const Duration(minutes: 15, seconds: 30),
              averagePace: const Duration(minutes: 6, seconds: 12),
              paceTrend: RunVoicePaceTrend.steady,
            ),
            _config(
              RunVoiceLanguage.korean,
              includeElapsedTime: true,
              includeAveragePace: true,
            ),
          );
          expect(
            message,
            '목표 거리의 절반을 지났습니다. 일정한 페이스를 잘 유지하고 있어요. 운동 시간은 15분 30초입니다. '
            '평균 페이스는 킬로미터당 6분 12초입니다.',
          );
        },
      );

      test('Simplified Chinese: slower pace trend appends the eval clause', () {
        final message = formatter.format(
          _targetHalfway(paceTrend: RunVoicePaceTrend.slower),
          _config(RunVoiceLanguage.simplifiedChinese),
        );
        expect(message, '您已到达目标距离的一半。 再加把劲，你做得很好！');
      });
    });

    group('target completed', () {
      test('English base line (analysis clause is always appended)', () {
        final message = formatter.format(
          _targetCompleted(),
          _config(RunVoiceLanguage.english),
        );
        expect(
          message,
          'You have reached your goal distance. Well done. You finished '
          '5 kilometers in 5 minutes.',
        );
      });

      test('Korean base line (analysis clause is always appended)', () {
        final message = formatter.format(
          _targetCompleted(),
          _config(RunVoiceLanguage.korean),
        );
        expect(message, '목표 거리를 완료했습니다. 수고하셨습니다. 총 5킬로미터를 5분에 완주했습니다.');
      });

      test('Simplified Chinese base line (analysis clause is always appended)', () {
        final message = formatter.format(
          _targetCompleted(),
          _config(RunVoiceLanguage.simplifiedChinese),
        );
        expect(message, '您已完成目标距离。做得好。 您用时5分完成了5公里。');
      });

      test(
        'Korean: full analysis + improvement (distance 5000, elapsed '
        '31:00, pace 6:12, trend slower)',
        () {
          final message = formatter.format(
            _targetCompleted(
              distanceMeters: 5000,
              elapsed: const Duration(minutes: 31),
              averagePace: const Duration(minutes: 6, seconds: 12),
              paceTrend: RunVoicePaceTrend.slower,
            ),
            _config(RunVoiceLanguage.korean),
          );
          expect(
            message,
            '목표 거리를 완료했습니다. 수고하셨습니다. 총 5킬로미터를 31분에 완주했고, 평균 페이스는 킬로미터당 6분 '
            '12초입니다. 후반에 페이스가 조금 떨어졌어요. 다음엔 끝까지 일정하게 달려보세요.',
          );
        },
      );

      test(
        'English: full analysis + improvement (distance 5000, elapsed '
        '25:00, pace 5:00, trend faster)',
        () {
          final message = formatter.format(
            _targetCompleted(
              distanceMeters: 5000,
              elapsed: const Duration(minutes: 25),
              averagePace: const Duration(minutes: 5),
              paceTrend: RunVoicePaceTrend.faster,
            ),
            _config(RunVoiceLanguage.english),
          );
          expect(
            message,
            'You have reached your goal distance. Well done. You '
            'finished 5 kilometers in 25 minutes, at an average pace of '
            '5 minutes per kilometer. You picked up the pace at the '
            'end — excellent!',
          );
        },
      );

      test(
        'Simplified Chinese: full analysis + improvement (distance 5000, '
        'elapsed 20:00, pace 4:00, trend steady)',
        () {
          final message = formatter.format(
            _targetCompleted(
              distanceMeters: 5000,
              elapsed: const Duration(minutes: 20),
              averagePace: const Duration(minutes: 4),
              paceTrend: RunVoicePaceTrend.steady,
            ),
            _config(RunVoiceLanguage.simplifiedChinese),
          );
          expect(
            message,
            '您已完成目标距离。做得好。 您用时20分完成了5公里，平均配速每公里4分。 全程配速稳定，非常出色！',
          );
        },
      );

      test(
        'Korean: averagePace null drops the pace part of analysis but '
        'keeps improvement',
        () {
          final message = formatter.format(
            _targetCompleted(
              distanceMeters: 3000,
              elapsed: const Duration(minutes: 18),
              paceTrend: RunVoicePaceTrend.faster,
            ),
            _config(RunVoiceLanguage.korean),
          );
          expect(
            message,
            '목표 거리를 완료했습니다. 수고하셨습니다. 총 3킬로미터를 18분에 완주했습니다. 마지막까지 페이스를 잘 '
            '끌어올렸어요. 아주 좋아요!',
          );
        },
      );

      test(
        'Korean: paceTrend null omits improvement but analysis with pace '
        'still appears',
        () {
          final message = formatter.format(
            _targetCompleted(
              distanceMeters: 5000,
              elapsed: const Duration(minutes: 30),
              averagePace: const Duration(minutes: 6),
            ),
            _config(RunVoiceLanguage.korean),
          );
          expect(
            message,
            '목표 거리를 완료했습니다. 수고하셨습니다. 총 5킬로미터를 30분에 완주했고, 평균 페이스는 킬로미터당 '
            '6분입니다.',
          );
        },
      );
    });
  });
}
