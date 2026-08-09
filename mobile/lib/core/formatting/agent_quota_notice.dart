/// Shared copy for the AI surfaces that refuse to generate because the runner
/// has spent the day's quota.
///
/// The backend owns both the limit and the reset boundary: the quota
/// reservations in `functions/src/agent/` answer a refusal with
/// `retryAfterDate`, the next Singapore calendar day as `YYYY-MM-DD`. This
/// helper only turns that value into a sentence. It never derives a reset day
/// of its own — a client clock in another timezone would name the wrong one —
/// and it deliberately never states the limit, which the client is never told
/// and which is configurable server-side.
///
/// A missing or unparseable date still produces a notice, naming no day. The
/// runner learning that the surface resets is the point; silently serving
/// generic copy with no explanation is what manual test scripts 6.2.1 and
/// 6.2.3 recorded as a defect.
String agentQuotaResetNotice({
  required String? retryAfterDate,
  required String subject,
}) {
  final day = _displayDate(retryAfterDate);
  return day == null
      ? 'Daily limit reached — $subject unlocks again tomorrow.'
      : 'Daily limit reached — $subject unlocks again on $day.';
}

/// `2026-08-09` -> `9 August 2026`. Returns null for anything that is not
/// exactly a valid `YYYY-MM-DD` date, so a malformed value degrades to the
/// dateless notice rather than rendering a half-parsed string.
String? _displayDate(String? isoDate) {
  if (isoDate == null) return null;
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(isoDate.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  // Rejects a day the month does not have (2026-02-30), which the range check
  // above lets through: DateTime rolls such a value over into the next month.
  final resolved = DateTime(year, month, day);
  if (resolved.month != month || resolved.day != day) return null;
  return '$day ${_monthNames[month - 1]} $year';
}

const List<String> _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
