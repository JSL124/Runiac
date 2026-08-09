/// Closed set of reasons for reporting another user's profile or Friends-row
/// entry.
///
/// [value] is the exact string persisted to the `reason` field of a
/// `reports/{reporterUid}_{targetId}` document. The admin console's severity
/// mapping (`toReportSeverity()` in `website/src/lib/admin/live-data.ts`)
/// keys off that string containing "harass", "abuse", or "unsafe" (case
/// insensitive) to render HIGH severity; every other reason renders MEDIUM.
/// [harassmentOrAbuse] and [unsafeConduct] exercise the HIGH path;
/// [cheatingOrGamingTheSystem], [spamOrImpersonation], and [other] exercise
/// the MEDIUM path. Never derive display copy from [value] — use [label].
enum ReportUserReason {
  harassmentOrAbuse('harassment_or_abuse', 'Harassment or abuse'),
  unsafeConduct('unsafe_conduct', 'Unsafe or reckless conduct'),
  cheatingOrGamingTheSystem(
    'cheating_or_gaming_the_system',
    'Cheating or gaming the system',
  ),
  spamOrImpersonation('spam_or_impersonation', 'Spam or impersonation'),
  other('other', 'Other');

  const ReportUserReason(this.value, this.label);

  /// Exact string persisted to Firestore.
  final String value;

  /// Human-readable label shown in the reason picker.
  final String label;
}
