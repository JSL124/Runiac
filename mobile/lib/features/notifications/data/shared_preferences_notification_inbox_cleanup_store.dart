import 'package:shared_preferences/shared_preferences.dart';

import '../domain/services/notification_inbox_legacy_cleanup.dart';

/// Per-user marker recording that the one-time inbox backlog sweep has run.
///
/// The version suffix in the default key is deliberate: if a future defect
/// ever requires another sweep, bumping it re-runs the cleanup once per runner
/// instead of resetting everyone's history repeatedly.
class SharedPreferencesNotificationInboxCleanupStore
    implements NotificationInboxCleanupStore {
  SharedPreferencesNotificationInboxCleanupStore({
    required this.uidProvider,
    this.keyPrefix = 'runiac.notificationInbox.legacyCleanup.v1',
  });

  final String? Function() uidProvider;
  final String keyPrefix;

  String? _key() {
    final uid = uidProvider();
    if (uid == null || uid.isEmpty) {
      return null;
    }
    return '$keyPrefix.$uid';
  }

  @override
  Future<bool> hasCleaned() async {
    final key = _key();
    if (key == null) {
      // Signed out: report the sweep as already done so nothing runs without
      // an owner to scope it to.
      return true;
    }
    final preferences = await SharedPreferences.getInstance();
    return preferences.getBool(key) ?? false;
  }

  @override
  Future<void> markCleaned() async {
    final key = _key();
    if (key == null) {
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(key, true);
  }
}
