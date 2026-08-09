import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../legal/runiac_legal_link_launcher.dart';
import '../legal/runiac_legal_urls.dart';
import '../legal/runiac_url_opener.dart';
import '../theme/runiac_colors.dart';

/// Consent sentence with tappable Terms and Privacy Policy links.
///
/// Stateful because [TapGestureRecognizer]s must be disposed with the widget.
class RuniacLegalLinksText extends StatefulWidget {
  const RuniacLegalLinksText({
    this.opener = const UrlLauncherOpener(),
    super.key,
  });

  /// Seam so tests can record the requested URL without launching a browser.
  final RuniacUrlOpener opener;

  @override
  State<RuniacLegalLinksText> createState() => _RuniacLegalLinksTextState();
}

class _RuniacLegalLinksTextState extends State<RuniacLegalLinksText> {
  late final TapGestureRecognizer _termsRecognizer;
  late final TapGestureRecognizer _privacyRecognizer;

  @override
  void initState() {
    super.initState();
    _termsRecognizer = TapGestureRecognizer()
      ..onTap = () => _open(RuniacLegalUrls.terms);
    _privacyRecognizer = TapGestureRecognizer()
      ..onTap = () => _open(RuniacLegalUrls.privacy);
  }

  @override
  void dispose() {
    _termsRecognizer.dispose();
    _privacyRecognizer.dispose();
    super.dispose();
  }

  Future<void> _open(String url) {
    return openRuniacLegalUrl(context, opener: widget.opener, url: url);
  }

  @override
  Widget build(BuildContext context) {
    const linkStyle = TextStyle(
      color: RuniacColors.primaryBlue,
      fontWeight: FontWeight.w800,
    );

    return Text.rich(
      TextSpan(
        text: 'By continuing you agree to our ',
        children: [
          TextSpan(
            text: 'Terms',
            style: linkStyle,
            recognizer: _termsRecognizer,
            mouseCursor: SystemMouseCursors.click,
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: linkStyle,
            recognizer: _privacyRecognizer,
            mouseCursor: SystemMouseCursors.click,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: RuniacColors.textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.45,
      ),
    );
  }
}
