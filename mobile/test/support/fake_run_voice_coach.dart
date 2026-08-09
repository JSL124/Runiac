import 'package:runiac_app/features/run/voice/domain/models/run_voice_session_config.dart';
import 'package:runiac_app/features/run/voice/domain/models/run_voice_snapshot.dart';
import 'package:runiac_app/features/run/voice/domain/ports/run_voice_coach.dart';

class FakeRunVoiceCoach implements RunVoiceCoach {
  int startCalls = 0;
  int stopCalls = 0;
  int activeSessionCount = 0;
  final List<RunVoiceSnapshot> snapshots = [];
  bool throwOnSnapshot = false;
  RunVoiceSessionConfig? lastConfig;

  @override
  Future<void> startSession(RunVoiceSessionConfig config) async {
    startCalls += 1;
    activeSessionCount = 1;
    lastConfig = config;
  }

  @override
  Future<void> onSnapshot(RunVoiceSnapshot snapshot) async {
    if (throwOnSnapshot) {
      throw StateError('FakeRunVoiceCoach.onSnapshot forced failure');
    }
    snapshots.add(snapshot);
  }

  @override
  Future<void> stopSession() async {
    stopCalls += 1;
    activeSessionCount = 0;
  }
}
