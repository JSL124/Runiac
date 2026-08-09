/// Shared relative-time phrase formatting, e.g. `'3 days ago'`.
///
/// Callers pass an already-resolved [DateTime] (converted defensively from
/// its source, e.g. a Firestore `Timestamp`); this helper only turns an
/// elapsed duration into short, consistent display copy. A future [since]
/// (clock skew, or a server timestamp not yet visible locally) is clamped to
/// zero so it never renders a negative duration.
String relativeAgoPhrase(DateTime since, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final elapsed = reference.difference(since);
  final clamped = elapsed.isNegative ? Duration.zero : elapsed;

  if (clamped.inMinutes < 1) return 'just now';
  if (clamped.inMinutes < 60) return _unitsAgo(clamped.inMinutes, 'minute');
  if (clamped.inHours < 24) return _unitsAgo(clamped.inHours, 'hour');
  if (clamped.inDays < 30) return _unitsAgo(clamped.inDays, 'day');
  if (clamped.inDays < 365) return _unitsAgo(clamped.inDays ~/ 30, 'month');
  return _unitsAgo(clamped.inDays ~/ 365, 'year');
}

String _unitsAgo(int value, String unit) {
  final count = value < 1 ? 1 : value;
  return '$count $unit${count == 1 ? '' : 's'} ago';
}
