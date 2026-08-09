import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../../auth/domain/runiac_auth_service.dart';
import '../../data/firebase_account_deletion_repository.dart';
import '../delete_account_screen.dart';

/// Account → Delete account, the last row on the Account screen.
///
/// Styled apart from the manage rows and from Sign out — red text on a red
/// hairline rather than the shared white card — because it is the one row here
/// whose outcome cannot be undone. It is a plain navigation row: nothing is
/// deleted from this widget, and every confirmation lives on the screen it
/// opens, so a mis-tap costs a back press.
class AccountDeleteRow extends StatelessWidget {
  const AccountDeleteRow({
    required this.authRepository,
    this.deletionRepository,
    super.key,
  });

  final RuniacAuthRepository authRepository;

  /// Injectable so a widget test can drive the flow without Firebase. Built
  /// lazily on tap rather than in the constructor: constructing the real
  /// repository reaches for `FirebaseFunctions.instanceFor`, and the Account
  /// screen must not require Firebase just to render this row.
  final AccountDeletionRepository? deletionRepository;

  @override
  Widget build(BuildContext context) {
    return RuniacTappableSurface(
      key: const ValueKey('account_delete_row'),
      semanticLabel: 'Delete account',
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: RuniacColors.errorRed.withValues(alpha: 0.28)),
      ),
      onTap: () => _open(context),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: RuniacColors.errorRed.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.delete_outline_rounded,
              color: RuniacColors.errorRed,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Delete account',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: RuniacColors.errorRed,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Erase your account and data',
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
          Icon(
            Icons.chevron_right_rounded,
            color: RuniacColors.errorRed.withValues(alpha: 0.7),
            size: 22,
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeleteAccountScreen(
          authRepository: authRepository,
          deletionRepository:
              deletionRepository ?? FirebaseAccountDeletionRepository(),
        ),
      ),
    );
  }
}
