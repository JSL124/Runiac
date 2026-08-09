/// Marks an inbox item as a notification that genuinely reached the runner.
///
/// It lives inside `data` because `firestore.rules` pins the document's
/// top-level keys, and `data` is the one free-form map a client may write.
const notificationInboxDeliveredAtKey = 'deliveredAtMillis';

class NotificationInboxItem {
  const NotificationInboxItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    this.readAt,
    this.deletedAt,
    this.data = const <String, Object?>{},
    this.clientManaged = false,
  });

  final String id;
  final String title;
  final String body;

  /// When the notification actually reached the runner. Never a future instant:
  /// the inbox records deliveries, not schedules.
  final DateTime createdAt;
  final DateTime? readAt;
  final DateTime? deletedAt;
  final Map<String, Object?> data;

  /// True for items this app wrote itself (local plan notifications), false for
  /// items a Cloud Function delivered. Only the client-written ones are in
  /// scope for the one-time legacy cleanup.
  final bool clientManaged;

  bool get isRead => readAt != null;

  bool get isDeleted => deletedAt != null;

  /// Whether this item records a notification that actually fired, rather than
  /// one the old schedule-time write left behind.
  bool get recordsDelivery => data.containsKey(notificationInboxDeliveredAtKey);

  NotificationInboxItem copyWith({DateTime? readAt, DateTime? deletedAt}) {
    return NotificationInboxItem(
      id: id,
      title: title,
      body: body,
      createdAt: createdAt,
      readAt: readAt ?? this.readAt,
      deletedAt: deletedAt ?? this.deletedAt,
      data: data,
      clientManaged: clientManaged,
    );
  }
}
