/// Canonical addresses of the hosted Runiac legal documents.
///
/// The documents live on the marketing site so they can be corrected without
/// shipping an app release, and so the same URLs can be reused for App Store
/// Connect and Play Console metadata. Every in-app legal link resolves through
/// this class — no screen should hardcode its own URL string.
class RuniacLegalUrls {
  const RuniacLegalUrls._();

  /// Production origin of the marketing site. No trailing slash.
  static const String base = 'https://fyp-website-v2.vercel.app';

  /// Terms of Service, doubling as the EULA link required on the paywall.
  static const String terms = '$base/legal/terms';

  /// Privacy Policy.
  static const String privacy = '$base/legal/privacy';

  /// Account and data deletion request instructions.
  static const String accountDeletion = '$base/legal/account-deletion';

  /// Cookie notice. Website-only concern, kept here for completeness.
  static const String cookies = '$base/legal/cookies';
}
