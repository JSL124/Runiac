import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_confirm_dialog.dart';
import '../../../core/widgets/runiac_sheet_primitives.dart';
import '../../../core/widgets/runiac_sheet_scaffold.dart';
import '../domain/models/friends_read_model.dart';

enum FriendAction { remove, block, report }

Future<FriendAction?> showFriendActionsSheet(
  BuildContext context,
  FriendUserReadModel user,
) {
  return showModalBottomSheet<FriendAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) {
      final firstName = user.displayName.trim().split(RegExp(r'\s+')).first;
      return RuniacSheetScaffold(
        title: user.displayName,
        subtitle: 'Choose an action',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RuniacSheetActionTile(
              key: const ValueKey('friends-remove-action'),
              icon: Icons.person_remove_rounded,
              title: 'Remove Friend',
              caption: 'Remove $firstName from your friends',
              onTap: () => Navigator.of(context).pop(FriendAction.remove),
            ),
            const SizedBox(height: 10),
            RuniacSheetActionTile(
              key: const ValueKey('friends-block-action'),
              icon: Icons.block_rounded,
              tint: RuniacColors.errorRed,
              titleColor: RuniacColors.errorRed,
              title: 'Block',
              caption: 'Stop all contact both ways',
              onTap: () => Navigator.of(context).pop(FriendAction.block),
            ),
            const SizedBox(height: 10),
            RuniacSheetActionTile(
              key: const ValueKey('friends-report-action'),
              icon: Icons.flag_rounded,
              title: 'Report',
              caption: 'Tell us what went wrong',
              onTap: () => Navigator.of(context).pop(FriendAction.report),
            ),
            const SizedBox(height: 4),
            const RuniacSheetCancelButton(),
          ],
        ),
      );
    },
  );
}

Future<bool> showFriendActionConfirmation(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  bool isDestructive = true,
  IconData icon = Icons.help_outline_rounded,
}) async {
  return showRuniacConfirmDialog(
    context,
    title: title,
    body: body,
    confirmLabel: confirmLabel,
    icon: icon,
    isDestructive: isDestructive,
    confirmKey: const ValueKey('friends-confirm-action'),
  );
}

String friendActionConfirmationBody(FriendAction action) {
  return switch (action) {
    FriendAction.remove =>
      'This removes the friendship. You can send a new friend request after 24 hours.',
    FriendAction.block =>
      'This removes the friendship and pending requests in both directions. '
          'You will no longer appear to each other in Friends, Search, or Feed.',
    // Report opens its own reason-picker sheet instead of this yes/no
    // confirmation dialog, so this body copy is never shown for it.
    FriendAction.report => '',
  };
}
