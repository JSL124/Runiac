import 'package:url_launcher/url_launcher.dart';

/// Opens an external web address.
///
/// Exists as an interface so widgets can take an opener as a constructor seam
/// and widget tests can record the requested URL without touching a platform
/// channel — the same pattern the app uses for repositories and other
/// platform-backed collaborators.
abstract class RuniacUrlOpener {
  /// Opens [url]. Returns false when the platform refused to handle it.
  Future<bool> open(Uri url);
}

/// Default opener backed by `url_launcher`.
///
/// Prefers an in-app browser view (SFSafariViewController / Chrome Custom Tab)
/// so the user keeps their place in Runiac while still seeing the real address
/// bar, and falls back to the system browser when the platform cannot provide
/// one.
class UrlLauncherOpener implements RuniacUrlOpener {
  const UrlLauncherOpener();

  @override
  Future<bool> open(Uri url) async {
    try {
      final opened = await launchUrl(url, mode: LaunchMode.inAppBrowserView);
      if (opened) {
        return true;
      }
    } on Object {
      // Fall through to the external browser attempt below.
    }
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
