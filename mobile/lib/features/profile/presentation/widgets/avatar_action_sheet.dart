import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_sheet_primitives.dart';
import '../../../../core/widgets/runiac_sheet_scaffold.dart';
import '../../../you/presentation/widgets/you_surface_primitives.dart';

enum AvatarSheetAction { choosePhoto, removePhoto }

/// Mirrors `showFriendActionsSheet` in `friends_action_sheets.dart`: the same
/// `RuniacSheetScaffold`/`RuniacSheetActionTile`/`RuniacSheetCancelButton`
/// chrome, applied to the Edit Profile avatar tap target. "Remove photo" is
/// rendered inert (not hidden) when [hasPhoto] is false, matching how a
/// disabled sheet action reads elsewhere in the app.
Future<AvatarSheetAction?> showAvatarActionSheet(
  BuildContext context, {
  required bool hasPhoto,
}) {
  return showModalBottomSheet<AvatarSheetAction>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (context) {
      return RuniacSheetScaffold(
        title: 'Profile photo',
        subtitle: 'Choose an action',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RuniacSheetActionTile(
              key: const ValueKey('avatar-choose-photo-action'),
              icon: Icons.photo_camera_outlined,
              title: 'Choose photo',
              caption: 'Pick a photo from your library',
              onTap: () =>
                  Navigator.of(context).pop(AvatarSheetAction.choosePhoto),
            ),
            const SizedBox(height: 10),
            RuniacSheetActionTile(
              key: const ValueKey('avatar-remove-photo-action'),
              icon: Icons.person_off_outlined,
              tint: RuniacColors.errorRed,
              titleColor: RuniacColors.errorRed,
              title: 'Remove photo',
              caption: 'Go back to your initials',
              onTap: hasPhoto
                  ? () => Navigator.of(
                      context,
                    ).pop(AvatarSheetAction.removePhoto)
                  : null,
            ),
            const SizedBox(height: 4),
            const RuniacSheetCancelButton(),
          ],
        ),
      );
    },
  );
}

/// One-time-per-action visibility gate shown before every avatar upload
/// (never before a remove, which only reduces visibility). Cancelling this
/// dialog must leave the caller exactly where they were, with no upload ever
/// attempted — callers are required to check the returned value before
/// touching the upload gateway.
Future<bool> showAvatarVisibilityConfirmation(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: RuniacColors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        icon: Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: RuniacColors.primaryBlue.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.visibility_outlined,
            color: RuniacColors.primaryBlue,
            size: 28,
          ),
        ),
        title: const Text(
          'Your photo will be visible to others',
          textAlign: TextAlign.center,
          style: YouTextStyles.cardTitle,
        ),
        content: const Text(
          'Your profile photo is shown to other runners on the leaderboard '
          'and can be viewed by anyone who has the link, including runners '
          'you have blocked. Blocking only stops in-app contact — it does '
          'not hide a photo link that has already been shared.',
          textAlign: TextAlign.center,
          style: YouTextStyles.body,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            key: const ValueKey('avatar-visibility-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('avatar-visibility-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: RuniacColors.primaryBlue,
              foregroundColor: RuniacColors.white,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      );
    },
  );
  return result == true;
}
