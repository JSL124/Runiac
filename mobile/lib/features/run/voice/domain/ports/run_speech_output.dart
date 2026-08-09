abstract interface class RunSpeechOutput {
  Future<void> initialize();

  Future<void> speak(String message, {String? languageTag});

  Future<void> stop();
}
