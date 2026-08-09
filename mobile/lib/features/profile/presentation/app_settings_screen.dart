import 'package:flutter/material.dart';

import '../../../core/haptics/runiac_haptics_scope.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../settings/data/firestore_profile_visibility_repository.dart';
import '../../settings/data/shared_preferences_app_settings_repository.dart';
import '../../settings/domain/models/app_settings.dart';
import '../../settings/domain/repositories/app_settings_repository.dart';
import '../../settings/domain/repositories/profile_visibility_repository.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({
    this.settingsRepository = const SharedPreferencesAppSettingsRepository(),
    this.profileVisibilityRepository =
        const FirestoreProfileVisibilityRepository(),
    super.key,
  });

  final AppSettingsRepository settingsRepository;

  /// Source for the profile-visibility switch. Unlike [settingsRepository],
  /// which is on-device preference state, this one is backed by the runner's
  /// `userProfiles/{uid}` document — the switch has to be readable by the
  /// server, because the server is what enforces it.
  final ProfileVisibilityRepository profileVisibilityRepository;

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

enum _VisibilityState { loading, ready, unavailable }

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  AppSettings _settings = AppSettings.defaults;
  var _visibilityState = _VisibilityState.loading;
  var _statsHidden = false;
  var _savingVisibility = false;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
    _restoreVisibility();
  }

  Future<void> _restoreSettings() async {
    final settings = await widget.settingsRepository.loadSettings();
    if (!mounted) {
      return;
    }
    setState(() {
      _settings = settings;
    });
  }

  Future<void> _setSettings(AppSettings settings) async {
    setState(() {
      _settings = settings;
    });
    await widget.settingsRepository.saveSettings(settings);
  }

  Future<void> _restoreVisibility() async {
    try {
      final hidden = await widget.profileVisibilityRepository
          .loadStatsHidden();
      if (!mounted) {
        return;
      }
      setState(() {
        _statsHidden = hidden;
        _visibilityState = _VisibilityState.ready;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      // Never fall back to a guessed value. Showing "off" for a runner who is
      // actually hidden — or "on" for one who is not — is worse than showing
      // that the control could not be loaded.
      setState(() {
        _visibilityState = _VisibilityState.unavailable;
      });
    }
  }

  Future<void> _setStatsHidden(bool hidden) async {
    final previous = _statsHidden;
    setState(() {
      _statsHidden = hidden;
      _savingVisibility = true;
    });
    try {
      await widget.profileVisibilityRepository.saveStatsHidden(hidden: hidden);
      if (!mounted) {
        return;
      }
      setState(() {
        _savingVisibility = false;
      });
    } on Object {
      if (!mounted) {
        return;
      }
      // The switch reverts to what is actually stored, so it never shows a
      // privacy state the backend did not accept.
      setState(() {
        _statsHidden = previous;
        _savingVisibility = false;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update profile visibility. Please try again.',
            ),
          ),
        );
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
              title: 'Settings',
              tooltip: 'Back to Account',
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
                      const _SectionLabel('UNITS'),
                      const SizedBox(height: 8),
                      _UnitsCard(
                        distanceUnit: _settings.distanceUnit,
                        onChanged: (unit) {
                          _setSettings(_settings.copyWith(distanceUnit: unit));
                        },
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('PROFILE VISIBILITY'),
                      const SizedBox(height: 8),
                      _ProfileVisibilityCard(
                        state: _visibilityState,
                        statsHidden: _statsHidden,
                        isSaving: _savingVisibility,
                        onChanged: _setStatsHidden,
                      ),
                      const SizedBox(height: 20),
                      const _SectionLabel('APP COMFORT'),
                      const SizedBox(height: 8),
                      _AppComfortCard(
                        settings: _settings,
                        onHapticChanged: (value) {
                          _setSettings(
                            _settings.copyWith(hapticFeedbackEnabled: value),
                          );
                          RuniacHapticsScope.maybeOf(
                            context,
                          )?.setEnabled(value);
                        },
                        onKeepScreenOnChanged: (value) {
                          _setSettings(
                            _settings.copyWith(keepScreenOnDuringRun: value),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const _FooterNote(),
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

class _UnitsCard extends StatelessWidget {
  const _UnitsCard({required this.distanceUnit, required this.onChanged});

  final DistanceUnit distanceUnit;
  final ValueChanged<DistanceUnit> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            const _IconTile(icon: Icons.straighten_outlined),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Distance units',
                    style: TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Used for the live run display.',
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
            const SizedBox(width: 10),
            _DistanceUnitSelector(value: distanceUnit, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

class _DistanceUnitSelector extends StatelessWidget {
  const _DistanceUnitSelector({required this.value, required this.onChanged});

  final DistanceUnit value;
  final ValueChanged<DistanceUnit> onChanged;

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
          mainAxisSize: MainAxisSize.min,
          children: [
            _DistanceUnitOption(
              key: const ValueKey('settings-distance-unit-km'),
              label: 'Km',
              selected: value == DistanceUnit.kilometers,
              onTap: () => onChanged(DistanceUnit.kilometers),
            ),
            _DistanceUnitOption(
              key: const ValueKey('settings-distance-unit-mi'),
              label: 'Mi',
              selected: value == DistanceUnit.miles,
              onTap: () => onChanged(DistanceUnit.miles),
            ),
          ],
        ),
      ),
    );
  }
}

class _DistanceUnitOption extends StatelessWidget {
  const _DistanceUnitOption({
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
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            width: 44,
            height: 32,
            decoration: BoxDecoration(
              color: selected ? RuniacColors.primaryBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected
                      ? RuniacColors.white
                      : RuniacColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one switch that decides whether other runners see this runner's record.
///
/// The switch stores a preference; it does not hide anything by itself. The
/// values are withheld by `getRunnerPublicProfile`, which is why the subtitle
/// promises what it does.
class _ProfileVisibilityCard extends StatelessWidget {
  const _ProfileVisibilityCard({
    required this.state,
    required this.statsHidden,
    required this.isSaving,
    required this.onChanged,
  });

  final _VisibilityState state;
  final bool statsHidden;
  final bool isSaving;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Column(
        children: [
          _SwitchRow(
            switchKey: const ValueKey('settings-private-profile-switch'),
            icon: Icons.lock_outline,
            title: 'Private profile',
            subtitle: statsHidden
                ? 'On — other runners see only your name, photo and rank.'
                : 'Hide your level, streak, distance and badges from other '
                      'runners.',
            value: statsHidden,
            // Disabled while loading or in-flight, and when the preference
            // could not be reached at all.
            onChanged: state == _VisibilityState.ready && !isSaving
                ? onChanged
                : null,
          ),
          if (state == _VisibilityState.unavailable)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 0, 14, 13),
              child: Text(
                key: ValueKey('settings-private-profile-unavailable'),
                'Sign in to change who can see your running record.',
                style: TextStyle(
                  color: RuniacColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AppComfortCard extends StatelessWidget {
  const _AppComfortCard({
    required this.settings,
    required this.onHapticChanged,
    required this.onKeepScreenOnChanged,
  });

  final AppSettings settings;
  final ValueChanged<bool> onHapticChanged;
  final ValueChanged<bool> onKeepScreenOnChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.border),
      ),
      child: Column(
        children: [
          _SwitchRow(
            switchKey: const ValueKey('settings-haptic-switch'),
            icon: Icons.vibration_outlined,
            title: 'Haptic feedback',
            subtitle: 'Feel a light vibration for run alerts and taps.',
            value: settings.hapticFeedbackEnabled,
            onChanged: onHapticChanged,
          ),
          const Divider(
            height: 1,
            thickness: 1,
            color: RuniacColors.border,
            indent: 58,
          ),
          _SwitchRow(
            switchKey: const ValueKey('settings-keep-screen-on-switch'),
            icon: Icons.brightness_high_outlined,
            title: 'Keep screen on during runs',
            subtitle: 'Prevents your phone from locking mid-run.',
            value: settings.keepScreenOnDuringRun,
            onChanged: onKeepScreenOnChanged,
          ),
        ],
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

  /// Null renders the row as read-only, which is how an unresolved or in-flight
  /// preference is shown.
  final ValueChanged<bool>? onChanged;

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

class _FooterNote extends StatelessWidget {
  const _FooterNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        'Your unit choice currently applies to the live run display only; '
        'historical and summary distances stay in kilometers for now.',
        style: TextStyle(
          color: RuniacColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.3,
        ),
      ),
    );
  }
}
