enum NotificationPreference {
  planStartReminder,
  todaysPlanReminder,
  missedRunNudge,
  planUpdates,
  socialActivity,
}

class NotificationCenterSettings {
  const NotificationCenterSettings({
    required this.notificationsEnabled,
    required this.planStartReminderEnabled,
    required this.todaysPlanReminderEnabled,
    required this.missedRunNudgeEnabled,
    required this.planUpdatesEnabled,
    this.socialActivityEnabled = true,
  });

  static const defaults = NotificationCenterSettings(
    notificationsEnabled: true,
    planStartReminderEnabled: true,
    todaysPlanReminderEnabled: true,
    missedRunNudgeEnabled: true,
    planUpdatesEnabled: true,
    socialActivityEnabled: true,
  );

  final bool notificationsEnabled;
  final bool planStartReminderEnabled;
  final bool todaysPlanReminderEnabled;
  final bool missedRunNudgeEnabled;
  final bool planUpdatesEnabled;
  final bool socialActivityEnabled;

  int get enabledPreferenceCount {
    return [
      planStartReminderEnabled,
      todaysPlanReminderEnabled,
      missedRunNudgeEnabled,
      planUpdatesEnabled,
      socialActivityEnabled,
    ].where((enabled) => enabled).length;
  }

  bool isPreferenceEnabled(NotificationPreference preference) {
    return switch (preference) {
      NotificationPreference.planStartReminder => planStartReminderEnabled,
      NotificationPreference.todaysPlanReminder => todaysPlanReminderEnabled,
      NotificationPreference.missedRunNudge => missedRunNudgeEnabled,
      NotificationPreference.planUpdates => planUpdatesEnabled,
      NotificationPreference.socialActivity => socialActivityEnabled,
    };
  }

  NotificationCenterSettings copyWith({
    bool? notificationsEnabled,
    bool? planStartReminderEnabled,
    bool? todaysPlanReminderEnabled,
    bool? missedRunNudgeEnabled,
    bool? planUpdatesEnabled,
    bool? socialActivityEnabled,
  }) {
    return NotificationCenterSettings(
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
      planStartReminderEnabled:
          planStartReminderEnabled ?? this.planStartReminderEnabled,
      todaysPlanReminderEnabled:
          todaysPlanReminderEnabled ?? this.todaysPlanReminderEnabled,
      missedRunNudgeEnabled:
          missedRunNudgeEnabled ?? this.missedRunNudgeEnabled,
      planUpdatesEnabled: planUpdatesEnabled ?? this.planUpdatesEnabled,
      socialActivityEnabled:
          socialActivityEnabled ?? this.socialActivityEnabled,
    );
  }

  NotificationCenterSettings withPreference(
    NotificationPreference preference,
    bool enabled,
  ) {
    return switch (preference) {
      NotificationPreference.planStartReminder => copyWith(
        planStartReminderEnabled: enabled,
      ),
      NotificationPreference.todaysPlanReminder => copyWith(
        todaysPlanReminderEnabled: enabled,
      ),
      NotificationPreference.missedRunNudge => copyWith(
        missedRunNudgeEnabled: enabled,
      ),
      NotificationPreference.planUpdates => copyWith(
        planUpdatesEnabled: enabled,
      ),
      NotificationPreference.socialActivity => copyWith(
        socialActivityEnabled: enabled,
      ),
    };
  }

  @override
  bool operator ==(Object other) {
    return other is NotificationCenterSettings &&
        other.notificationsEnabled == notificationsEnabled &&
        other.planStartReminderEnabled == planStartReminderEnabled &&
        other.todaysPlanReminderEnabled == todaysPlanReminderEnabled &&
        other.missedRunNudgeEnabled == missedRunNudgeEnabled &&
        other.planUpdatesEnabled == planUpdatesEnabled &&
        other.socialActivityEnabled == socialActivityEnabled;
  }

  @override
  int get hashCode {
    return Object.hash(
      notificationsEnabled,
      planStartReminderEnabled,
      todaysPlanReminderEnabled,
      missedRunNudgeEnabled,
      planUpdatesEnabled,
      socialActivityEnabled,
    );
  }
}
