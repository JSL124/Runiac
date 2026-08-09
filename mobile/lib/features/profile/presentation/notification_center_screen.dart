import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../notifications/data/shared_preferences_notification_center_settings_repository.dart';
import '../../notifications/domain/models/notification_center_settings.dart';
import '../../notifications/domain/repositories/notification_center_settings_repository.dart';

/// Notification preferences, grouped by what the notification is about.
///
/// There is a master switch above the groups, and turning it off disables the
/// individual toggles rather than silently overriding them — [_DisabledHelper]
/// explains why they are greyed out, so the user's per-group choices are still
/// visible and are restored when the master is turned back on.
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({
    this.settingsRepository =
        const SharedPreferencesNotificationCenterSettingsRepository(),
    this.onSettingsChanged,
    super.key,
  });

  final NotificationCenterSettingsRepository settingsRepository;
  final ValueChanged<NotificationCenterSettings>? onSettingsChanged;

  static const _beforeRunRows = <_NotificationPreferenceRowData>[
    _NotificationPreferenceRowData(
      preference: NotificationPreference.planStartReminder,
      icon: Icons.event_available_outlined,
      title: 'Plan-start reminder',
      subtitle: 'Notifies you 2 hours, 1 hour, and 10 min before your run.',
    ),
    _NotificationPreferenceRowData(
      preference: NotificationPreference.todaysPlanReminder,
      icon: Icons.today_outlined,
      title: "Today's plan reminder",
      subtitle: 'Notifies you at 12:00 AM if a plan is scheduled for today.',
    ),
  ];

  static const _afterRunRows = <_NotificationPreferenceRowData>[
    _NotificationPreferenceRowData(
      preference: NotificationPreference.missedRunNudge,
      icon: Icons.directions_run_outlined,
      title: 'Missed run nudge',
      subtitle:
          "Notifies you 1 hour and 2 hours after today's plan time if you haven't run.",
    ),
    _NotificationPreferenceRowData(
      preference: NotificationPreference.planUpdates,
      icon: Icons.update_outlined,
      title: 'Plan updates',
      subtitle: 'Know when your coach adjusts an upcoming plan.',
    ),
  ];

  static const _socialRows = <_NotificationPreferenceRowData>[
    _NotificationPreferenceRowData(
      preference: NotificationPreference.socialActivity,
      icon: Icons.favorite_border,
      title: 'Likes and comments',
      subtitle: 'When a friend likes or comments on your shared run.',
    ),
  ];

  static const _notificationRows = [
    ..._beforeRunRows,
    ..._afterRunRows,
    ..._socialRows,
  ];

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  NotificationCenterSettings _settings = NotificationCenterSettings.defaults;

  @override
  void initState() {
    super.initState();
    _restoreSettings();
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

  Future<void> _setSettings(NotificationCenterSettings settings) async {
    setState(() {
      _settings = settings;
    });
    await widget.settingsRepository.saveSettings(settings);
    widget.onSettingsChanged?.call(settings);
  }

  @override
  Widget build(BuildContext context) {
    final notificationsEnabled = _settings.notificationsEnabled;
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Notification Center',
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
                      _MasterNotificationsCard(
                        enabled: notificationsEnabled,
                        enabledCount: _settings.enabledPreferenceCount,
                        totalCount:
                            NotificationCenterScreen._notificationRows.length,
                        onChanged: (value) {
                          _setSettings(
                            _settings.copyWith(notificationsEnabled: value),
                          );
                        },
                      ),
                      if (!notificationsEnabled) ...[
                        const SizedBox(height: 10),
                        const _DisabledHelper(),
                      ],
                      const SizedBox(height: 20),
                      _NotificationGroup(
                        label: 'BEFORE YOUR RUN',
                        rows: NotificationCenterScreen._beforeRunRows,
                        settings: _settings,
                        onRowChanged: (preference, value) {
                          _setSettings(
                            _settings.withPreference(preference, value),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _NotificationGroup(
                        label: 'AFTER YOUR RUN',
                        rows: NotificationCenterScreen._afterRunRows,
                        settings: _settings,
                        onRowChanged: (preference, value) {
                          _setSettings(
                            _settings.withPreference(preference, value),
                          );
                        },
                      ),
                      const SizedBox(height: 20),
                      _NotificationGroup(
                        label: 'SOCIAL',
                        rows: NotificationCenterScreen._socialRows,
                        settings: _settings,
                        onRowChanged: (preference, value) {
                          _setSettings(
                            _settings.withPreference(preference, value),
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

class _MasterNotificationsCard extends StatelessWidget {
  const _MasterNotificationsCard({
    required this.enabled,
    required this.enabledCount,
    required this.totalCount,
    required this.onChanged,
  });

  final bool enabled;
  final int enabledCount;
  final int totalCount;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final subtitle = enabled
        ? '$enabledCount of $totalCount reminders on'
        : 'All reminders paused';
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
            _IconTile(icon: Icons.notifications_outlined, enabled: enabled),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Notifications',
                    style: TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
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
              value: enabled,
              onChanged: onChanged,
              activeThumbColor: RuniacColors.primaryBlue,
            ),
          ],
        ),
      ),
    );
  }
}

class _DisabledHelper extends StatelessWidget {
  const _DisabledHelper();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.sectionSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RuniacColors.cardBorder),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          'Turn Notifications on to edit reminder controls.',
          style: TextStyle(
            color: RuniacColors.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class _NotificationGroup extends StatelessWidget {
  const _NotificationGroup({
    required this.label,
    required this.rows,
    required this.settings,
    required this.onRowChanged,
  });

  final String label;
  final List<_NotificationPreferenceRowData> rows;
  final NotificationCenterSettings settings;
  final void Function(NotificationPreference preference, bool value)
  onRowChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(label),
        const SizedBox(height: 8),
        _NotificationPreferenceSection(
          settings: settings,
          rows: rows,
          onRowChanged: onRowChanged,
        ),
      ],
    );
  }
}

class _NotificationPreferenceSection extends StatelessWidget {
  const _NotificationPreferenceSection({
    required this.settings,
    required this.rows,
    required this.onRowChanged,
  });

  final NotificationCenterSettings settings;
  final List<_NotificationPreferenceRowData> rows;
  final void Function(NotificationPreference preference, bool value)
  onRowChanged;

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
          for (var index = 0; index < rows.length; index++) ...[
            _NotificationPreferenceRow(
              row: rows[index],
              notificationsEnabled: settings.notificationsEnabled,
              rowEnabled: settings.isPreferenceEnabled(rows[index].preference),
              onChanged: (value) => onRowChanged(rows[index].preference, value),
            ),
            if (index != rows.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: RuniacColors.border,
                indent: 58,
              ),
          ],
        ],
      ),
    );
  }
}

class _NotificationPreferenceRow extends StatelessWidget {
  const _NotificationPreferenceRow({
    required this.row,
    required this.notificationsEnabled,
    required this.rowEnabled,
    required this.onChanged,
  });

  final _NotificationPreferenceRowData row;
  final bool notificationsEnabled;
  final bool rowEnabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final controlsEnabled = notificationsEnabled && rowEnabled;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconTile(icon: row.icon, enabled: controlsEnabled),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: controlsEnabled
                        ? RuniacColors.textPrimary
                        : RuniacColors.textSecondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  row.subtitle,
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
            value: controlsEnabled,
            onChanged: notificationsEnabled ? onChanged : null,
            activeThumbColor: RuniacColors.primaryBlue,
          ),
        ],
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, required this.enabled});

  final IconData icon;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: enabled
            ? RuniacColors.sectionSurfaceStrong
            : RuniacColors.innerTileSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        icon,
        color: enabled ? RuniacColors.primaryBlue : RuniacColors.textSecondary,
        size: 18,
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

class _NotificationPreferenceRowData {
  const _NotificationPreferenceRowData({
    required this.preference,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final NotificationPreference preference;
  final IconData icon;
  final String title;
  final String subtitle;
}
