import 'package:shared_preferences/shared_preferences.dart';

import '../repositories/notification_center_settings_repository.dart';
import '../repositories/notification_preference_mirror.dart';

/// Keeps the server-side `notificationPreferences/{uid}.socialActivityEnabled`
/// mirror in sync with the on-device Notification Center Social toggle.
///
/// KNOWN LIMITATION: `shared_preferences` is per-device and stays the only
/// source of truth for every Notification Center toggle, including this one.
/// With two devices signed into the same account, the server ends up
/// honouring whichever device most recently mirrored a value — there is no
/// cross-device reconciliation. The clean fix would make this one derived
/// key Firestore-authoritative (a read-through, not a device-local
/// write-behind mirror); that is deliberately deferred, not solved here.
class NotificationPreferenceMirrorService {
  NotificationPreferenceMirrorService({
    required this.settingsRepository,
    required this.mirror,
    required this.ownerUidProvider,
    this.keyPrefix = 'runiac.notificationCenter.lastMirroredSocialActivity',
  });

  final NotificationCenterSettingsRepository settingsRepository;
  final NotificationPreferenceMirror mirror;
  final String? Function() ownerUidProvider;
  final String keyPrefix;

  /// In-memory fast path so a rebuild/reopen within the same process does
  /// not re-read `shared_preferences` just to discover nothing changed.
  final Map<String, bool> _lastMirroredByUid = <String, bool>{};

  /// Recomputes the effective Social-activity value and mirrors it to
  /// Firestore, but only when it differs from the last value this device
  /// successfully mirrored for the current uid. No-ops when signed out.
  ///
  /// Never throws: mirroring is best-effort and must not block or surface to
  /// the UI.
  Future<void> syncSocialActivity() async {
    final uid = ownerUidProvider();
    if (uid == null || uid.isEmpty) {
      return;
    }

    final settings = await settingsRepository.loadSettings();
    final effectiveValue =
        settings.notificationsEnabled && settings.socialActivityEnabled;

    if (_lastMirroredByUid[uid] == effectiveValue) {
      return;
    }

    final preferences = await SharedPreferences.getInstance();
    final key = _lastMirroredKey(uid);
    if (preferences.getBool(key) == effectiveValue) {
      // A previous run (possibly a previous cold start) already mirrored
      // this exact value; remember it in memory so the next call short
      // circuits without touching shared_preferences again.
      _lastMirroredByUid[uid] = effectiveValue;
      return;
    }

    try {
      await mirror.mirror(uid: uid, socialActivityEnabled: effectiveValue);
      _lastMirroredByUid[uid] = effectiveValue;
      await preferences.setBool(key, effectiveValue);
    } catch (_) {
      // Best-effort mirror: a Firestore failure here must never surface to
      // the UI or block the Notification Center toggle from taking local
      // effect.
    }
  }

  String _lastMirroredKey(String uid) => '$keyPrefix.$uid';
}
