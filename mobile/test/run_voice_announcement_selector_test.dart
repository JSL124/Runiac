import 'package:flutter_test/flutter_test.dart';

import 'package:runiac_app/features/run/voice/domain/models/run_voice_announcement.dart';
import 'package:runiac_app/features/run/voice/domain/services/run_voice_announcement_selector.dart';

RunVoiceAnnouncement _announcement({
  required String id,
  required RunVoiceAnnouncementType type,
  required int priority,
}) {
  return RunVoiceAnnouncement(
    id: id,
    type: type,
    priority: priority,
    distanceMeters: null,
    elapsed: Duration.zero,
    averagePace: null,
  );
}

void main() {
  group('PriorityRunVoiceAnnouncementSelector', () {
    const selector = PriorityRunVoiceAnnouncementSelector();

    test('returns null for an empty candidate list', () {
      expect(selector.select(const []), isNull);
    });

    test('selects the higher-priority candidate', () {
      final distance = _announcement(
        id: 'distance:1000',
        type: RunVoiceAnnouncementType.distanceMilestone,
        priority: 50,
      );
      final targetCompleted = _announcement(
        id: 'target:completed',
        type: RunVoiceAnnouncementType.targetCompleted,
        priority: 100,
      );

      final selected = selector.select([distance, targetCompleted]);

      expect(selected, targetCompleted);
    });

    test('order of candidates does not affect the winner', () {
      final distance = _announcement(
        id: 'distance:1000',
        type: RunVoiceAnnouncementType.distanceMilestone,
        priority: 50,
      );
      final targetCompleted = _announcement(
        id: 'target:completed',
        type: RunVoiceAnnouncementType.targetCompleted,
        priority: 100,
      );

      final selected = selector.select([targetCompleted, distance]);

      expect(selected, targetCompleted);
    });
  });
}
