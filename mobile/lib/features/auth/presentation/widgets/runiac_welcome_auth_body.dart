import 'package:flutter/material.dart';

import '../../../../core/legal/runiac_url_opener.dart';
import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_legal_links_text.dart';
import 'runiac_auth_buttons.dart';
import 'runiac_auth_fields.dart';

class RuniacWelcomeAuthBody extends StatelessWidget {
  const RuniacWelcomeAuthBody({
    required this.onSignup,
    required this.onLogin,
    this.legalUrlOpener = const UrlLauncherOpener(),
    super.key,
  });

  final VoidCallback onSignup;
  final VoidCallback onLogin;

  /// Seam so tests can observe the legal links without launching a browser.
  final RuniacUrlOpener legalUrlOpener;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 56),
        const RuniacHeroMark(),
        const SizedBox(height: 24),
        const Text(
          'Build a running habit that sticks, one easy step at a time.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: RuniacColors.primaryBlue,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 84),
        RuniacAuthButton(label: 'Sign up', onPressed: onSignup),
        const SizedBox(height: 14),
        RuniacAuthButton(
          label: 'Log in',
          onPressed: onLogin,
          variant: RuniacAuthButtonVariant.secondary,
        ),
        const SizedBox(height: 18),
        RuniacLegalLinksText(opener: legalUrlOpener),
      ],
    );
  }
}
