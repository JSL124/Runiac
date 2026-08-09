import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_back_header.dart';
import '../data/shared_preferences_run_voice_settings_repository.dart';
import '../domain/models/run_voice_coaching_settings.dart';
import '../domain/models/run_voice_language.dart';
import '../domain/repositories/run_voice_settings_repository.dart';
import 'run_voice_preview_page.dart';

/// Settings for spoken run updates — language, how often to announce, and what
/// each announcement includes.
///
/// Reached from the gear icon on the Run tab and configured once rather than
/// per run. Changes are written straight through to the repository as they are
/// made, so there is no save button and no unsaved state to lose.
///
/// **Preview voices** opens [RunVoicePreviewPage], which speaks a sample using
/// the current selection — text-to-speech voice availability varies by device
/// and language, so hearing it is the only reliable check.
class RunVoiceSettingsPage extends StatefulWidget {
  const RunVoiceSettingsPage({
    this.settingsRepository =
        const SharedPreferencesRunVoiceSettingsRepository(),
    super.key,
  });

  final RunVoiceSettingsRepository settingsRepository;

  @override
  State<RunVoiceSettingsPage> createState() => _RunVoiceSettingsPageState();
}

class _RunVoiceSettingsPageState extends State<RunVoiceSettingsPage> {
  RunVoiceCoachingSettings _settings = RunVoiceCoachingSettings.defaults;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
  }

  Future<void> _restoreSettings() async {
    var settings = RunVoiceCoachingSettings.defaults;
    try {
      settings = await widget.settingsRepository.load();
    } on Object {
      settings = RunVoiceCoachingSettings.defaults;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
    });
  }

  Future<void> _setSettings(RunVoiceCoachingSettings settings) async {
    setState(() {
      _settings = settings;
    });
    await widget.settingsRepository.save(settings);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _settings.enabled;
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Run Settings',
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
                      const _SectionLabel('VOICE COACHING'),
                      const SizedBox(height: 8),
                      _VoiceCoachingCard(
                        settings: _settings,
                        onEnabledChanged: (value) {
                          _setSettings(_settings.copyWith(enabled: value));
                        },
                        onLanguageChanged: (language) {
                          _setSettings(
                            _settings.copyWith(language: language),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('DISTANCE UPDATES'),
                      const SizedBox(height: 8),
                      _DistanceUpdatesCard(
                        enabled: enabled,
                        value: _settings.distanceIntervalMeters,
                        onChanged: (meters) {
                          _setSettings(
                            _settings.copyWith(distanceIntervalMeters: meters),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('TIME UPDATES'),
                      const SizedBox(height: 8),
                      _TimeUpdatesCard(
                        enabled: enabled,
                        value: _settings.timeInterval,
                        onChanged: (interval) {
                          if (interval == null) {
                            _setSettings(
                              _settings.copyWith(clearTimeInterval: true),
                            );
                          } else {
                            _setSettings(
                              _settings.copyWith(timeInterval: interval),
                            );
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('ANNOUNCEMENT DETAILS'),
                      const SizedBox(height: 8),
                      _AnnouncementDetailsCard(
                        enabled: enabled,
                        includeElapsedTime: _settings.includeElapsedTime,
                        includeAveragePace: _settings.includeAveragePace,
                        onIncludeElapsedTimeChanged: (value) {
                          _setSettings(
                            _settings.copyWith(includeElapsedTime: value),
                          );
                        },
                        onIncludeAveragePaceChanged: (value) {
                          _setSettings(
                            _settings.copyWith(includeAveragePace: value),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('PREVIEW'),
                      const SizedBox(height: 8),
                      _PreviewCard(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const RunVoicePreviewPage(),
                            ),
                          );
                        },
                      ),
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

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: const ValueKey('voice_preview_button'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _IconTile(icon: Icons.play_circle_outline),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Preview voices',
                        style: TextStyle(
                          color: RuniacColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Play and hear each spoken announcement.',
                        style: TextStyle(
                          color: RuniacColors.textSecondary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: RuniacColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceCoachingCard extends StatelessWidget {
  const _VoiceCoachingCard({
    required this.settings,
    required this.onEnabledChanged,
    required this.onLanguageChanged,
  });

  final RunVoiceCoachingSettings settings;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<RunVoiceLanguage> onLanguageChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = settings.enabled;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Column(
        children: [
          _SwitchRow(
            switchKey: const ValueKey('voice_coaching_enabled_switch'),
            icon: Icons.record_voice_over_outlined,
            title: 'Voice progress updates',
            subtitle: 'Hear spoken updates about your run as you go.',
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: RuniacColors.border,
            indent: 58,
          ),
          Opacity(
            opacity: enabled ? 1 : 0.45,
            child: IgnorePointer(
              ignoring: !enabled,
              child: _LanguageRow(
                key: const ValueKey('voice_language_control'),
                language: settings.language,
                onChanged: onLanguageChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DistanceUpdatesCard extends StatelessWidget {
  const _DistanceUpdatesCard({
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  final bool enabled;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: IgnorePointer(
          ignoring: !enabled,
          child: _DistanceIntervalRow(
            key: const ValueKey('voice_distance_interval_control'),
            value: value,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _TimeUpdatesCard extends StatelessWidget {
  const _TimeUpdatesCard({
    required this.enabled,
    required this.value,
    required this.onChanged,
  });

  final bool enabled;
  final Duration? value;
  final ValueChanged<Duration?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: IgnorePointer(
          ignoring: !enabled,
          child: _TimeIntervalRow(
            key: const ValueKey('voice_time_interval_control'),
            value: value,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _AnnouncementDetailsCard extends StatelessWidget {
  const _AnnouncementDetailsCard({
    required this.enabled,
    required this.includeElapsedTime,
    required this.includeAveragePace,
    required this.onIncludeElapsedTimeChanged,
    required this.onIncludeAveragePaceChanged,
  });

  final bool enabled;
  final bool includeElapsedTime;
  final bool includeAveragePace;
  final ValueChanged<bool> onIncludeElapsedTimeChanged;
  final ValueChanged<bool> onIncludeAveragePaceChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: IgnorePointer(
          ignoring: !enabled,
          child: Column(
            children: [
              _SwitchRow(
                switchKey: const ValueKey('voice_include_elapsed_switch'),
                icon: Icons.timer_outlined,
                title: 'Include elapsed time',
                subtitle: 'Announce your total time elapsed during updates.',
                value: includeElapsedTime,
                onChanged: onIncludeElapsedTimeChanged,
              ),
              const Divider(
                height: 1,
                thickness: 1,
                color: RuniacColors.border,
                indent: 58,
              ),
              _SwitchRow(
                switchKey: const ValueKey('voice_include_pace_switch'),
                icon: Icons.speed_outlined,
                title: 'Include average pace',
                subtitle: 'Announce your average pace during updates.',
                value: includeAveragePace,
                onChanged: onIncludeAveragePaceChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.language,
    required this.onChanged,
    super.key,
  });

  final RunVoiceLanguage language;
  final ValueChanged<RunVoiceLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _IconTile(icon: Icons.translate_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Voice language',
                      style: TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Used for spoken run updates.',
                      style: TextStyle(
                        color: RuniacColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _LanguageSelector(value: language, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.value, required this.onChanged});

  final RunVoiceLanguage value;
  final ValueChanged<RunVoiceLanguage> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
                key: const ValueKey('voice-language-english'),
                label: 'English',
                selected: value == RunVoiceLanguage.english,
                onTap: () => onChanged(RunVoiceLanguage.english),
              ),
            ),
            Expanded(
              child: _SegmentOption(
                key: const ValueKey('voice-language-korean'),
                label: 'Korean',
                selected: value == RunVoiceLanguage.korean,
                onTap: () => onChanged(RunVoiceLanguage.korean),
              ),
            ),
            Expanded(
              child: _SegmentOption(
                key: const ValueKey('voice-language-simplified-chinese'),
                label: 'Chinese (Simplified)',
                selected: value == RunVoiceLanguage.simplifiedChinese,
                onTap: () => onChanged(RunVoiceLanguage.simplifiedChinese),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistanceIntervalRow extends StatelessWidget {
  const _DistanceIntervalRow({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _IconTile(icon: Icons.social_distance_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Distance updates',
                      style: TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Hear a spoken update at each distance milestone.',
                      style: TextStyle(
                        color: RuniacColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _DistanceIntervalSelector(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _DistanceIntervalSelector extends StatelessWidget {
  const _DistanceIntervalSelector({
    required this.value,
    required this.onChanged,
  });

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
                key: const ValueKey('voice-distance-500m'),
                label: 'Every 0.5 km',
                selected: value == 500,
                onTap: () => onChanged(500),
              ),
            ),
            Expanded(
              child: _SegmentOption(
                key: const ValueKey('voice-distance-1km'),
                label: 'Every 1 km',
                selected: value == 1000,
                onTap: () => onChanged(1000),
              ),
            ),
            Expanded(
              child: _SegmentOption(
                key: const ValueKey('voice-distance-2km'),
                label: 'Every 2 km',
                selected: value == 2000,
                onTap: () => onChanged(2000),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeIntervalRow extends StatelessWidget {
  const _TimeIntervalRow({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final Duration? value;
  final ValueChanged<Duration?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              _IconTile(icon: Icons.schedule_outlined),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Time updates',
                      style: TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Hear a spoken update at each time interval.',
                      style: TextStyle(
                        color: RuniacColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _TimeIntervalSelector(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TimeIntervalSelector extends StatelessWidget {
  const _TimeIntervalSelector({required this.value, required this.onChanged});

  final Duration? value;
  final ValueChanged<Duration?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
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
                key: const ValueKey('voice-time-off'),
                label: 'Off',
                selected: value == null,
                onTap: () => onChanged(null),
              ),
            ),
            Expanded(
              child: _SegmentOption(
                key: const ValueKey('voice-time-5min'),
                label: '5 min',
                selected: value == const Duration(minutes: 5),
                onTap: () => onChanged(const Duration(minutes: 5)),
              ),
            ),
            Expanded(
              child: _SegmentOption(
                key: const ValueKey('voice-time-10min'),
                label: '10 min',
                selected: value == const Duration(minutes: 10),
                onTap: () => onChanged(const Duration(minutes: 10)),
              ),
            ),
            Expanded(
              child: _SegmentOption(
                key: const ValueKey('voice-time-15min'),
                label: '15 min',
                selected: value == const Duration(minutes: 15),
                onTap: () => onChanged(const Duration(minutes: 15)),
              ),
            ),
          ],
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

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.switchKey,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(
            key: switchKey,
            value: value,
            onChanged: onChanged,
            activeThumbColor: RuniacColors.primaryBlue,
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: RuniacColors.sectionSurfaceStrong,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: RuniacColors.primaryBlue, size: 18),
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
