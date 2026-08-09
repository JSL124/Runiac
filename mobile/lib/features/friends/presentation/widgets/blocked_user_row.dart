import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../domain/models/friends_read_model.dart';
import 'friend_row_identity.dart';

class BlockedUserRow extends StatelessWidget {
  const BlockedUserRow({
    required this.user,
    required this.onUnblock,
    this.isActionInFlight = false,
    super.key,
  });

  final FriendUserReadModel user;
  final VoidCallback onUnblock;
  final bool isActionInFlight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: RuniacColors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RuniacColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              // A block denies visibility in both directions, so the
              // backend would always answer "not available" for a profile
              // lookup here — offering the tap would be dishonest UI.
              FriendRowBadge(user: user, enableProfileLink: false),
              const SizedBox(width: 12),
              Expanded(child: FriendRowName(user: user)),
              const SizedBox(width: 8),
              if (isActionInFlight)
                const SizedBox(
                  width: 44,
                  height: 44,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                RuniacTappableSurface(
                  key: ValueKey('friends-unblock-action-${user.userId}'),
                  semanticLabel: 'Unblock ${user.displayName}',
                  onTap: onUnblock,
                  height: 44,
                  alignment: Alignment.center,
                  borderRadius: BorderRadius.circular(999),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: RuniacColors.white,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: RuniacColors.border),
                  ),
                  child: const Text(
                    'Unblock',
                    style: TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
