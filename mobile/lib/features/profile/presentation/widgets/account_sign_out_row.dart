import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../../auth/domain/runiac_auth_service.dart';

/// The sign-out control in Settings.
///
/// Stateful because signing out is asynchronous and must not be startable
/// twice — the row disables itself while the request is in flight. Sign-out
/// also has to clear per-account cached state (route thumbnails, progress,
/// pending runs), so it goes through the auth service rather than calling
/// Firebase directly.
class AccountSignOutRow extends StatefulWidget {
  const AccountSignOutRow({required this.authRepository, super.key});

  final RuniacAuthRepository authRepository;

  @override
  State<AccountSignOutRow> createState() => _AccountSignOutRowState();
}

class _AccountSignOutRowState extends State<AccountSignOutRow> {
  bool _isSigningOut = false;
  bool _isConfirmingSignOut = false;

  Future<void> _handleSignOut() async {
    if (_isSigningOut) {
      return;
    }
    setState(() {
      _isSigningOut = true;
    });

    try {
      await widget.authRepository.signOut();
      if (!mounted) {
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isSigningOut = false;
      });
      final message = switch (error) {
        RuniacAuthException(:final userMessage) => userMessage,
        _ => 'We could not sign you out. Please try again.',
      };
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  void _showSignOutConfirmation() {
    if (_isSigningOut) {
      return;
    }
    setState(() {
      _isConfirmingSignOut = true;
    });
  }

  void _dismissSignOutConfirmation() {
    if (_isSigningOut) {
      return;
    }
    setState(() {
      _isConfirmingSignOut = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('account_sign_out_section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RuniacTappableSurface(
          semanticLabel: 'Sign out',
          borderRadius: BorderRadius.circular(18),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: RuniacColors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: RuniacColors.border),
          ),
          onTap: _isSigningOut ? null : _showSignOutConfirmation,
          child: Row(
            children: [
              const _SignOutIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isSigningOut ? 'Signing out...' : 'Sign out',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: RuniacColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    const Text(
                      'Return to the Runiac welcome screen',
                      // Matches the manage rows above: one line so this card
                      // keeps the same height as the rest of the list.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: RuniacColors.textSecondary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (_isSigningOut)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: RuniacColors.textSecondary,
                  size: 22,
                ),
            ],
          ),
        ),
        if (_isConfirmingSignOut) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            key: const ValueKey('account_sign_out_confirmation'),
            decoration: BoxDecoration(
              color: RuniacColors.sectionSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: RuniacColors.cardBorder),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Sign out?',
                    style: TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'You can sign back in with your email any time.',
                    style: TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSigningOut
                              ? null
                              : _dismissSignOutConfirmation,
                          child: const Text('Stay signed in'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: _isSigningOut ? null : _handleSignOut,
                          style: FilledButton.styleFrom(
                            backgroundColor: RuniacColors.accentOrange,
                          ),
                          child: Text(
                            _isSigningOut ? 'Signing out...' : 'Sign out',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SignOutIcon extends StatelessWidget {
  const _SignOutIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: RuniacColors.sectionSurfaceStrong,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(
        Icons.logout_rounded,
        color: RuniacColors.accentOrange,
        size: 18,
      ),
    );
  }
}
