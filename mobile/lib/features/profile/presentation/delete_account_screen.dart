import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_confirm_dialog.dart';
import '../../auth/domain/runiac_auth_service.dart';
import '../data/firebase_account_deletion_repository.dart';

/// Account → Delete account.
///
/// Store policy is why this screen exists: Apple Guideline 5.1.1(v) requires an
/// account-deletion path initiated inside the app, and Google Play's Data
/// deletion policy requires the same alongside the web request URL Runiac
/// already publishes. It is not a settings toggle and is not presented as one.
///
/// The screen's real job is informed consent. Deletion here is immediate and
/// irreversible — there is no grace period and no restore path — so it states
/// plainly what is erased, what is kept and why, and requires the word DELETE
/// to be typed before the confirmation dialog is even offered. Two gates rather
/// than one, because the cost of an accidental tap is unrecoverable.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({
    required this.authRepository,
    required this.deletionRepository,
    super.key,
  });

  final RuniacAuthRepository authRepository;
  final AccountDeletionRepository deletionRepository;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  static const String _requiredPhrase = 'DELETE';

  final TextEditingController _confirmation = TextEditingController();
  bool _isDeleting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  bool get _isPhraseTyped => _confirmation.text.trim() == _requiredPhrase;

  Future<void> _handleDelete() async {
    if (_isDeleting || !_isPhraseTyped) {
      return;
    }

    final confirmed = await showRuniacConfirmDialog(
      context,
      title: 'Delete your account?',
      body:
          'This erases your runs, plans, progress, and profile straight away. '
          'It cannot be undone, and it cannot be restored by signing in again.',
      // One word plus one word: the shared dialog gives both buttons an equal
      // half-width, and 'Delete forever' wrapped onto two lines there while
      // 'Cancel' stayed on one. 'Delete now' keeps the point the whole screen
      // is built around — that this happens immediately — on a single line.
      confirmLabel: 'Delete now',
      icon: Icons.delete_forever_rounded,
      confirmKey: const ValueKey('delete_account_dialog_confirm'),
    );
    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
    });

    try {
      await widget.deletionRepository.requestAccountDeletion();
    } catch (error) {
      if (!mounted) {
        return;
      }
      // Stay on the screen and stay signed in. Signing out after a failed
      // request would leave the runner unable to tell whether their account is
      // gone, and unable to retry.
      setState(() {
        _isDeleting = false;
        _errorMessage = switch (error) {
          AccountDeletionException(:final userMessage) => userMessage,
          _ => 'We could not delete your account. Please try again.',
        };
      });
      return;
    }

    // The server has already revoked this session's refresh tokens and disabled
    // the Auth user, so the local session is dead whether or not this sign-out
    // succeeds. Failing to clear it locally must not look like a failed
    // deletion, so the result is deliberately ignored.
    try {
      await widget.authRepository.signOut();
    } catch (_) {
      // Ignored, see above.
    }
    if (!mounted) {
      return;
    }
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Delete account',
              tooltip: 'Back to Account',
              onBack: _isDeleting ? null : () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(overscroll: false),
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _WarningCard(),
                      const SizedBox(height: 16),
                      const _DetailCard(
                        title: 'What is deleted',
                        icon: Icons.delete_outline_rounded,
                        tint: RuniacColors.errorRed,
                        lines: [
                          'Your profile, nickname, and photo',
                          'Every run, route, and activity summary',
                          'Your plans, XP, level, streak, and leaderboard standing',
                          'Your friends, challenges, badges, and notifications',
                          'Everything you posted to the feed',
                        ],
                      ),
                      const SizedBox(height: 12),
                      const _DetailCard(
                        title: 'What is kept, without your name on it',
                        icon: Icons.shield_outlined,
                        tint: RuniacColors.textSecondary,
                        lines: [
                          'Reports you filed or that were filed about you',
                          'Feedback you sent us',
                          'Records of administrator actions',
                        ],
                        footnote:
                            'These keep moderation honest — deleting an account '
                            'must not be a way to erase a report. Your name and '
                            'account are removed from them.',
                      ),
                      const SizedBox(height: 20),
                      _ConfirmationField(
                        controller: _confirmation,
                        enabled: !_isDeleting,
                        onChanged: (_) => setState(() {}),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        _ErrorNotice(message: _errorMessage!),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        key: const ValueKey('delete_account_submit'),
                        onPressed: _isPhraseTyped && !_isDeleting ? _handleDelete : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: RuniacColors.errorRed,
                          foregroundColor: RuniacColors.white,
                          // Two different disabled states that must not look
                          // alike. Before DELETE is typed the button is inert
                          // and should read as unavailable, so it goes grey.
                          // While the request is in flight it is also disabled
                          // — to block a double tap — but something IS
                          // happening, and a white spinner on the grey
                          // unavailable fill is almost invisible. Dimmed red
                          // keeps the spinner legible and keeps the button
                          // reading as armed rather than switched off.
                          disabledBackgroundColor: _isDeleting
                              ? RuniacColors.errorRed.withValues(alpha: 0.55)
                              : RuniacColors.border,
                          disabledForegroundColor: _isDeleting
                              ? RuniacColors.white
                              : RuniacColors.textSecondary,
                          minimumSize: const Size(0, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: _isDeleting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    RuniacColors.white,
                                  ),
                                ),
                              )
                            : const Text('Delete my account'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RuniacColors.errorRed.withValues(alpha: 0.22)),
      ),
      child: const Padding(
        padding: EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: RuniacColors.errorRed,
              size: 30,
            ),
            SizedBox(height: 12),
            Text(
              'This cannot be undone',
              style: TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Deleting your account takes effect immediately. There is no '
              'waiting period and no way to get your runs back afterwards. '
              'Signing up again starts a completely new account.',
              style: TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.icon,
    required this.tint,
    required this.lines,
    this.footnote,
  });

  final String title;
  final IconData icon;
  final Color tint;
  final List<String> lines;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final footnote = this.footnote;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: RuniacColors.cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: tint, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final line in lines) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: RuniacColors.textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ],
            if (footnote != null) ...[
              const SizedBox(height: 6),
              Text(
                footnote,
                style: TextStyle(
                  color: RuniacColors.textSecondary.withValues(alpha: 0.85),
                  fontSize: 12,
                  height: 1.45,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ConfirmationField extends StatelessWidget {
  const _ConfirmationField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Type DELETE to confirm',
          style: TextStyle(
            color: RuniacColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('delete_account_confirmation_field'),
          controller: controller,
          enabled: enabled,
          onChanged: onChanged,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [LengthLimitingTextInputFormatter(12)],
          decoration: InputDecoration(
            hintText: 'DELETE',
            filled: true,
            fillColor: RuniacColors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: RuniacColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: RuniacColors.errorRed),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: RuniacColors.border),
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.errorRed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RuniacColors.errorRed.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: RuniacColors.errorRed,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: RuniacColors.textPrimary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
