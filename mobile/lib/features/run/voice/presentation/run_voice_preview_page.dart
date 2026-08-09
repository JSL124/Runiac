import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_back_header.dart';
import '../domain/models/run_voice_announcement.dart';
import '../domain/models/run_voice_language.dart';
import '../domain/models/run_voice_session_config.dart';
import '../domain/ports/run_speech_output.dart';
import '../domain/services/run_voice_message_formatter.dart';
import '../infrastructure/flutter_tts_run_speech_output.dart';

/// Lets the user play back every voice-coaching announcement in the
/// currently-selected language so they can hear exactly what will be
/// spoken during a run, without starting one.
///
/// The default [RunSpeechOutput] ([FlutterTtsRunSpeechOutput]) is only
/// constructed in [State.initState], never as a constructor default value,
/// so building this widget never touches a platform channel and the
/// constructor can stay `const`.
class RunVoicePreviewPage extends StatefulWidget {
  const RunVoicePreviewPage({
    super.key,
    this.speechOutput,
    this.formatter = const LocalizedRunVoiceMessageFormatter(),
  });

  final RunSpeechOutput? speechOutput;
  final RunVoiceMessageFormatter formatter;

  @override
  State<RunVoicePreviewPage> createState() => _RunVoicePreviewPageState();
}

class _RunVoicePreviewPageState extends State<RunVoicePreviewPage> {
  late final RunSpeechOutput _speechOutput;
  RunVoiceLanguage _language = RunVoiceLanguage.english;

  @override
  void initState() {
    super.initState();
    _speechOutput = widget.speechOutput ?? FlutterTtsRunSpeechOutput();
  }

  @override
  void dispose() {
    _speechOutput.stop();
    super.dispose();
  }

  Future<void> _play(_PreviewItem item) async {
    final text = widget.formatter.format(
      item.announcement,
      item.configFor(_language),
    );
    try {
      await _speechOutput.speak(text, languageTag: _language.ttsLocale);
    } on Object {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voice playback is unavailable on this device.'),
        ),
      );
    }
  }

  Future<void> _stop() async {
    try {
      await _speechOutput.stop();
    } on Object {
      // Stopping a device with no active/available speech engine is a
      // no-op from the user's perspective.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Voice Preview',
              tooltip: 'Back',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(
                  context,
                ).copyWith(overscroll: false),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Tap Play to hear each announcement. Requires '
                        'device audio. The start message is chosen at '
                        'random each run.',
                        style: TextStyle(
                          color: RuniacColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const _SectionLabel('LANGUAGE'),
                      const SizedBox(height: 8),
                      _LanguageCard(
                        language: _language,
                        onChanged: (language) {
                          setState(() {
                            _language = language;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          key: const ValueKey('preview_stop_button'),
                          onPressed: _stop,
                          icon: const Icon(Icons.stop_circle_outlined),
                          label: const Text('Stop'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: RuniacColors.primaryBlue,
                            side: const BorderSide(
                              color: RuniacColors.cardBorder,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('ANNOUNCEMENTS'),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _previewItems.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        _PreviewItemCard(
                          item: _previewItems[i],
                          language: _language,
                          formatter: widget.formatter,
                          onPlay: _play,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({required this.language, required this.onChanged});

  final RunVoiceLanguage language;
  final ValueChanged<RunVoiceLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: DecoratedBox(
          key: const ValueKey('preview_language_control'),
          decoration: BoxDecoration(
            color: RuniacColors.sectionSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RuniacColors.cardBorder),
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Row(
              children: [
                Expanded(
                  child: _SegmentOption(
                    key: const ValueKey('preview-language-english'),
                    label: 'English',
                    selected: language == RunVoiceLanguage.english,
                    onTap: () => onChanged(RunVoiceLanguage.english),
                  ),
                ),
                Expanded(
                  child: _SegmentOption(
                    key: const ValueKey('preview-language-korean'),
                    label: 'Korean',
                    selected: language == RunVoiceLanguage.korean,
                    onTap: () => onChanged(RunVoiceLanguage.korean),
                  ),
                ),
                Expanded(
                  child: _SegmentOption(
                    key: const ValueKey(
                      'preview-language-simplified-chinese',
                    ),
                    label: 'Chinese (Simplified)',
                    selected: language == RunVoiceLanguage.simplifiedChinese,
                    onTap: () =>
                        onChanged(RunVoiceLanguage.simplifiedChinese),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SegmentOption extends StatelessWidget {
  const _SegmentOption({
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Ink(
              height: 32,
              decoration: BoxDecoration(
                color: selected
                    ? RuniacColors.primaryBlue
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      color: selected
                          ? RuniacColors.white
                          : RuniacColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewItemCard extends StatelessWidget {
  const _PreviewItemCard({
    required this.item,
    required this.language,
    required this.formatter,
    required this.onPlay,
  });

  final _PreviewItem item;
  final RunVoiceLanguage language;
  final RunVoiceMessageFormatter formatter;
  final ValueChanged<_PreviewItem> onPlay;

  @override
  Widget build(BuildContext context) {
    final text = formatter.format(item.announcement, item.configFor(language));
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text,
                    style: const TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              key: item.playKey,
              onPressed: () => onPlay(item),
              icon: const Icon(Icons.play_arrow, size: 18),
              label: const Text('Play'),
              style: ElevatedButton.styleFrom(
                backgroundColor: RuniacColors.primaryBlue,
                foregroundColor: RuniacColors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: RuniacColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 0,
      ),
    );
  }
}

class _PreviewItem {
  const _PreviewItem({
    required this.title,
    required this.playKey,
    required this.announcement,
    required this.includeElapsedTime,
    required this.includeAveragePace,
    this.targetDistanceMeters,
  });

  final String title;
  final Key playKey;
  final RunVoiceAnnouncement announcement;
  final bool includeElapsedTime;
  final bool includeAveragePace;
  final double? targetDistanceMeters;

  RunVoiceSessionConfig configFor(RunVoiceLanguage language) {
    return RunVoiceSessionConfig(
      enabled: true,
      distanceIntervalMeters: 1000,
      timeInterval: null,
      includeElapsedTime: includeElapsedTime,
      includeAveragePace: includeAveragePace,
      language: language,
      targetDistanceMeters: targetDistanceMeters,
    );
  }
}

final List<_PreviewItem> _previewItems = <_PreviewItem>[
  _PreviewItem(
    title: 'Start',
    playKey: const ValueKey('preview_play_start'),
    announcement: const RunVoiceAnnouncement(
      id: 'preview-start',
      type: RunVoiceAnnouncementType.startEncouragement,
      priority: 0,
      distanceMeters: null,
      elapsed: Duration.zero,
      averagePace: null,
      variant: 0,
    ),
    includeElapsedTime: false,
    includeAveragePace: false,
  ),
  _PreviewItem(
    title: 'Distance 1 km',
    playKey: const ValueKey('preview_play_distance_full'),
    announcement: const RunVoiceAnnouncement(
      id: 'preview-distance-full',
      type: RunVoiceAnnouncementType.distanceMilestone,
      priority: 0,
      distanceMeters: 1000,
      elapsed: Duration(seconds: 372),
      averagePace: Duration(seconds: 372),
    ),
    includeElapsedTime: true,
    includeAveragePace: true,
  ),
  _PreviewItem(
    title: 'Time 10 min',
    playKey: const ValueKey('preview_play_time'),
    announcement: const RunVoiceAnnouncement(
      id: 'preview-time',
      type: RunVoiceAnnouncementType.timeMilestone,
      priority: 0,
      distanceMeters: null,
      elapsed: Duration(minutes: 10),
      averagePace: Duration(seconds: 372),
    ),
    includeElapsedTime: true,
    includeAveragePace: true,
  ),
  _PreviewItem(
    title: 'Target halfway',
    playKey: const ValueKey('preview_play_halfway'),
    announcement: const RunVoiceAnnouncement(
      id: 'preview-halfway',
      type: RunVoiceAnnouncementType.targetHalfway,
      priority: 0,
      distanceMeters: 2500,
      elapsed: Duration(minutes: 15, seconds: 30),
      averagePace: Duration(seconds: 372),
      paceTrend: RunVoicePaceTrend.steady,
    ),
    includeElapsedTime: true,
    includeAveragePace: true,
    targetDistanceMeters: 5000,
  ),
  _PreviewItem(
    title: 'Target completed',
    playKey: const ValueKey('preview_play_completed'),
    announcement: const RunVoiceAnnouncement(
      id: 'preview-completed',
      type: RunVoiceAnnouncementType.targetCompleted,
      priority: 0,
      distanceMeters: 5000,
      elapsed: Duration(minutes: 31),
      averagePace: Duration(seconds: 372),
      paceTrend: RunVoicePaceTrend.slower,
    ),
    includeElapsedTime: true,
    includeAveragePace: true,
    targetDistanceMeters: 5000,
  ),
];
