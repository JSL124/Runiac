import 'package:flutter/material.dart';

import 'runiac_url_opener.dart';

/// Shown when the platform cannot open a legal document.
const String runiacLegalLinkFailureMessage =
    'Could not open the page. Please check your connection and try again.';

/// Opens a hosted legal document, surfacing a SnackBar when the platform
/// refuses. Shared by every in-app legal link so the failure behaviour stays
/// identical across the welcome screen, paywall, About, and Privacy & Safety.
Future<void> openRuniacLegalUrl(
  BuildContext context, {
  required RuniacUrlOpener opener,
  required String url,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final opened = await opener.open(Uri.parse(url));
  if (opened) {
    return;
  }
  messenger?.showSnackBar(
    const SnackBar(content: Text(runiacLegalLinkFailureMessage)),
  );
}
