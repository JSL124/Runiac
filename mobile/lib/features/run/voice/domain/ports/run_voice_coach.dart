import '../models/run_voice_session_config.dart';
import '../models/run_voice_snapshot.dart';

abstract interface class RunVoiceCoach {
  Future<void> startSession(RunVoiceSessionConfig config);

  Future<void> onSnapshot(RunVoiceSnapshot snapshot);

  Future<void> stopSession();
}

class NoopRunVoiceCoach implements RunVoiceCoach {
  const NoopRunVoiceCoach();

  @override
  Future<void> startSession(RunVoiceSessionConfig config) async {}

  @override
  Future<void> onSnapshot(RunVoiceSnapshot snapshot) async {}

  @override
  Future<void> stopSession() async {}
}
