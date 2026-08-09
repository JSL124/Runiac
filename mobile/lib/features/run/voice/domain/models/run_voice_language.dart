enum RunVoiceLanguage { english, korean, simplifiedChinese }

extension RunVoiceLanguageTtsLocale on RunVoiceLanguage {
  String get ttsLocale {
    switch (this) {
      case RunVoiceLanguage.english:
        return 'en-US';
      case RunVoiceLanguage.korean:
        return 'ko-KR';
      case RunVoiceLanguage.simplifiedChinese:
        return 'zh-CN';
    }
  }
}
