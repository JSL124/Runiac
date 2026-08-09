/// Typed failure raised when a backend Challenge payload cannot be parsed into
/// an immutable read model.
///
/// The Challenge feature parses strictly: every field is validated, every enum
/// resolves through an exhaustive switch, and any malformed, missing, or
/// unexpected value raises this exception instead of silently substituting a
/// default or fabricating progress. Callers surface it as an unavailable-state
/// error; they never invent trusted values on the client.
class ChallengeParseException implements Exception {
  const ChallengeParseException(this.reason, {this.field});

  /// Machine-stable reason describing why the payload was rejected.
  final String reason;

  /// The offending field name, when a single field is responsible.
  final String? field;

  @override
  String toString() {
    final location = field == null ? '' : ' (field: $field)';
    return 'ChallengeParseException: $reason$location';
  }
}
