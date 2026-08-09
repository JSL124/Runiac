/// Best-effort mirror of a single derived notification-preference boolean
/// into the server-owned `notificationPreferences/{uid}` document.
///
/// This is deliberately narrow: `shared_preferences` stays the source of
/// truth for every Notification Center toggle. Only the one boolean a
/// backend emitter needs to read (whether feed like/comment notifications
/// should be delivered) is mirrored out, and only best-effort — a failure
/// here must never surface to the UI or block anything else in the app.
abstract interface class NotificationPreferenceMirror {
  Future<void> mirror({
    required String uid,
    required bool socialActivityEnabled,
  });
}

/// No-op implementation used by the static/demo composition and by widget
/// tests, so neither needs a Firestore dependency.
class NoopNotificationPreferenceMirror
    implements NotificationPreferenceMirror {
  const NoopNotificationPreferenceMirror();

  @override
  Future<void> mirror({
    required String uid,
    required bool socialActivityEnabled,
  }) async {}
}
