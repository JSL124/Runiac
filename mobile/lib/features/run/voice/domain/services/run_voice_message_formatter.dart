import '../models/run_voice_announcement.dart';
import '../models/run_voice_language.dart';
import '../models/run_voice_session_config.dart';

abstract interface class RunVoiceMessageFormatter {
  String format(RunVoiceAnnouncement announcement, RunVoiceSessionConfig config);
}

/// Localizes every [RunVoiceAnnouncementType] into an EN/KO/ZH sentence,
/// optionally appending an elapsed-time clause and/or an average-pace
/// clause per [RunVoiceSessionConfig.includeElapsedTime] and
/// [RunVoiceSessionConfig.includeAveragePace].
///
/// Time milestones are the one exception to the elapsed-time flag: the
/// elapsed minutes are the substance of the message itself, so they are
/// always stated regardless of [RunVoiceSessionConfig.includeElapsedTime].
class LocalizedRunVoiceMessageFormatter implements RunVoiceMessageFormatter {
  const LocalizedRunVoiceMessageFormatter();

  @override
  String format(
    RunVoiceAnnouncement announcement,
    RunVoiceSessionConfig config,
  ) {
    switch (announcement.type) {
      case RunVoiceAnnouncementType.startEncouragement:
        return _formatStartEncouragement(announcement, config);
      case RunVoiceAnnouncementType.distanceMilestone:
        return _formatDistanceMilestone(announcement, config);
      case RunVoiceAnnouncementType.timeMilestone:
        return _formatTimeMilestone(announcement, config);
      case RunVoiceAnnouncementType.targetHalfway:
        return _formatTargetHalfway(announcement, config);
      case RunVoiceAnnouncementType.targetCompleted:
        return _formatTargetCompleted(announcement, config);
    }
  }

  /// Selects one of four localized run-start encouragement lines using
  /// [RunVoiceAnnouncement.variant] (defaulting to 0 when unset).
  String _formatStartEncouragement(
    RunVoiceAnnouncement announcement,
    RunVoiceSessionConfig config,
  ) {
    final index = (announcement.variant ?? 0) % 4;
    switch (config.language) {
      case RunVoiceLanguage.english:
        const variants = <String>[
          "Let's start your run. You've got this!",
          'Time to run. Enjoy every step!',
          'Starting now — steady and strong!',
          'Here we go. Have a great run!',
        ];
        return variants[index];
      case RunVoiceLanguage.korean:
        const variants = <String>[
          '러닝을 시작합니다. 오늘도 힘내세요!',
          '천천히, 꾸준히. 시작합니다!',
          '오늘의 러닝을 시작합니다. 즐겁게 달려요!',
          '좋은 페이스로 시작해볼까요? 화이팅!',
        ];
        return variants[index];
      case RunVoiceLanguage.simplifiedChinese:
        const variants = <String>[
          '开始跑步。今天也加油！',
          '慢慢来，坚持住。开始吧！',
          '开始今天的跑步。享受每一步！',
          '让我们出发吧，跑个痛快！',
        ];
        return variants[index];
    }
  }

  String _formatDistanceMilestone(
    RunVoiceAnnouncement announcement,
    RunVoiceSessionConfig config,
  ) {
    final km = _km(announcement.distanceMeters ?? 0);
    final elapsed = announcement.elapsed;
    final pace = announcement.averagePace;
    final includeElapsed = config.includeElapsedTime;
    final includePace = config.includeAveragePace && pace != null;

    switch (config.language) {
      case RunVoiceLanguage.english:
        final buffer = StringBuffer(
          'You have completed $km kilometer${km == '1' ? '' : 's'}.',
        );
        if (includeElapsed) {
          buffer.write(' Your time is ${_durEn(elapsed)}.');
        }
        if (includePace) {
          buffer.write(' Your average pace is ${_durEn(pace)} per kilometer.');
        }
        return buffer.toString();
      case RunVoiceLanguage.korean:
        final buffer = StringBuffer('$km킬로미터를 완료했습니다.');
        if (includeElapsed) {
          buffer.write(' 운동 시간은 ${_durKo(elapsed)}입니다.');
        }
        if (includePace) {
          buffer.write(' 평균 페이스는 킬로미터당 ${_durKo(pace)}입니다.');
        }
        return buffer.toString();
      case RunVoiceLanguage.simplifiedChinese:
        final buffer = StringBuffer('您已完成$km公里。');
        if (includeElapsed) {
          buffer.write('运动时间${_durZh(elapsed)}。');
        }
        if (includePace) {
          buffer.write('平均配速每公里${_durZh(pace)}。');
        }
        return buffer.toString();
    }
  }

  String _formatTimeMilestone(
    RunVoiceAnnouncement announcement,
    RunVoiceSessionConfig config,
  ) {
    final minutes = announcement.elapsed.inMinutes;
    final pace = announcement.averagePace;
    final includePace = config.includeAveragePace && pace != null;

    switch (config.language) {
      case RunVoiceLanguage.english:
        final buffer = StringBuffer('$minutes minutes elapsed.');
        if (includePace) {
          buffer.write(' Your average pace is ${_durEn(pace)} per kilometer.');
        }
        return buffer.toString();
      case RunVoiceLanguage.korean:
        final buffer = StringBuffer('$minutes분 경과했습니다.');
        if (includePace) {
          buffer.write(' 평균 페이스는 킬로미터당 ${_durKo(pace)}입니다.');
        }
        return buffer.toString();
      case RunVoiceLanguage.simplifiedChinese:
        final buffer = StringBuffer('已经过$minutes分钟。');
        if (includePace) {
          buffer.write('平均配速每公里${_durZh(pace)}。');
        }
        return buffer.toString();
    }
  }

  String _formatTargetHalfway(
    RunVoiceAnnouncement announcement,
    RunVoiceSessionConfig config,
  ) {
    final elapsed = announcement.elapsed;
    final pace = announcement.averagePace;
    final trend = announcement.paceTrend;
    final includeElapsed = config.includeElapsedTime;
    final includePace = config.includeAveragePace && pace != null;

    switch (config.language) {
      case RunVoiceLanguage.english:
        final buffer = StringBuffer('You are halfway to your goal.');
        if (trend != null) {
          buffer.write(switch (trend) {
            RunVoicePaceTrend.faster =>
              ' Your pace is picking up — keep it going!',
            RunVoicePaceTrend.steady => " You're holding a steady pace.",
            RunVoicePaceTrend.slower => " Stay strong, you're doing great.",
          });
        }
        if (includeElapsed) {
          buffer.write(' Your time is ${_durEn(elapsed)}.');
        }
        if (includePace) {
          buffer.write(' Your average pace is ${_durEn(pace)} per kilometer.');
        }
        return buffer.toString();
      case RunVoiceLanguage.korean:
        final buffer = StringBuffer('목표 거리의 절반을 지났습니다.');
        if (trend != null) {
          buffer.write(switch (trend) {
            RunVoicePaceTrend.faster => ' 페이스가 점점 좋아지고 있어요. 이대로 유지해요!',
            RunVoicePaceTrend.steady => ' 일정한 페이스를 잘 유지하고 있어요.',
            RunVoicePaceTrend.slower => ' 조금만 더 힘내세요!',
          });
        }
        if (includeElapsed) {
          buffer.write(' 운동 시간은 ${_durKo(elapsed)}입니다.');
        }
        if (includePace) {
          buffer.write(' 평균 페이스는 킬로미터당 ${_durKo(pace)}입니다.');
        }
        return buffer.toString();
      case RunVoiceLanguage.simplifiedChinese:
        final buffer = StringBuffer('您已到达目标距离的一半。');
        if (trend != null) {
          buffer.write(switch (trend) {
            RunVoicePaceTrend.faster => ' 配速越来越好，保持下去！',
            RunVoicePaceTrend.steady => ' 配速很稳定，继续保持。',
            RunVoicePaceTrend.slower => ' 再加把劲，你做得很好！',
          });
        }
        if (includeElapsed) {
          buffer.write('运动时间${_durZh(elapsed)}。');
        }
        if (includePace) {
          buffer.write('平均配速每公里${_durZh(pace)}。');
        }
        return buffer.toString();
    }
  }

  String _formatTargetCompleted(
    RunVoiceAnnouncement announcement,
    RunVoiceSessionConfig config,
  ) {
    final km = _km(announcement.distanceMeters ?? 0);
    final elapsed = announcement.elapsed;
    final pace = announcement.averagePace;
    final trend = announcement.paceTrend;
    final hasPace = pace != null;

    switch (config.language) {
      case RunVoiceLanguage.english:
        final buffer = StringBuffer(
          'You have reached your goal distance. Well done.',
        );
        if (hasPace) {
          buffer.write(
            ' You finished $km kilometers in ${_durEn(elapsed)}, at an average pace of ${_durEn(pace)} per kilometer.',
          );
        } else {
          buffer.write(' You finished $km kilometers in ${_durEn(elapsed)}.');
        }
        if (trend != null) {
          buffer.write(switch (trend) {
            RunVoicePaceTrend.slower =>
              ' Your pace dipped in the later stretch — try to keep it even next time.',
            RunVoicePaceTrend.faster =>
              ' You picked up the pace at the end — excellent!',
            RunVoicePaceTrend.steady =>
              ' You kept a steady pace throughout. Great work!',
          });
        }
        return buffer.toString();
      case RunVoiceLanguage.korean:
        final buffer = StringBuffer('목표 거리를 완료했습니다. 수고하셨습니다.');
        if (hasPace) {
          buffer.write(
            ' 총 $km킬로미터를 ${_durKo(elapsed)}에 완주했고, 평균 페이스는 킬로미터당 ${_durKo(pace)}입니다.',
          );
        } else {
          buffer.write(' 총 $km킬로미터를 ${_durKo(elapsed)}에 완주했습니다.');
        }
        if (trend != null) {
          buffer.write(switch (trend) {
            RunVoicePaceTrend.slower => ' 후반에 페이스가 조금 떨어졌어요. 다음엔 끝까지 일정하게 달려보세요.',
            RunVoicePaceTrend.faster => ' 마지막까지 페이스를 잘 끌어올렸어요. 아주 좋아요!',
            RunVoicePaceTrend.steady => ' 처음부터 끝까지 안정적인 러닝이었어요. 훌륭해요!',
          });
        }
        return buffer.toString();
      case RunVoiceLanguage.simplifiedChinese:
        final buffer = StringBuffer('您已完成目标距离。做得好。');
        if (hasPace) {
          buffer.write(
            ' 您用时${_durZh(elapsed)}完成了$km公里，平均配速每公里${_durZh(pace)}。',
          );
        } else {
          buffer.write(' 您用时${_durZh(elapsed)}完成了$km公里。');
        }
        if (trend != null) {
          buffer.write(switch (trend) {
            RunVoicePaceTrend.slower => ' 后半程配速有所下降，下次试着保持匀速。',
            RunVoicePaceTrend.faster => ' 最后阶段配速提升了，非常棒！',
            RunVoicePaceTrend.steady => ' 全程配速稳定，非常出色！',
          });
        }
        return buffer.toString();
    }
  }

  String _km(int meters) {
    final value = meters / 1000;
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String _durKo(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0 && s > 0) {
      return '$m분 $s초';
    }
    if (m > 0) {
      return '$m분';
    }
    return '$s초';
  }

  String _durEn(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    final pieces = <String>[];
    if (m > 0) {
      pieces.add('$m minute${m == 1 ? '' : 's'}');
    }
    if (s > 0) {
      pieces.add('$s second${s == 1 ? '' : 's'}');
    }
    if (pieces.isEmpty) {
      return '0 seconds';
    }
    return pieces.join(' ');
  }

  String _durZh(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0 && s > 0) {
      return '$m分$s秒';
    }
    if (m > 0) {
      return '$m分';
    }
    return '$s秒';
  }
}
