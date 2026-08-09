import '../models/run_voice_announcement.dart';

abstract interface class RunVoiceAnnouncementSelector {
  RunVoiceAnnouncement? select(List<RunVoiceAnnouncement> candidates);
}

class PriorityRunVoiceAnnouncementSelector
    implements RunVoiceAnnouncementSelector {
  const PriorityRunVoiceAnnouncementSelector();

  @override
  RunVoiceAnnouncement? select(List<RunVoiceAnnouncement> candidates) {
    if (candidates.isEmpty) {
      return null;
    }
    var best = candidates.first;
    for (final candidate in candidates.skip(1)) {
      if (candidate.priority > best.priority) {
        best = candidate;
      }
    }
    return best;
  }
}
