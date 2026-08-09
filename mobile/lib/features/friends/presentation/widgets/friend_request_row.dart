import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../domain/models/friends_read_model.dart';
import 'friend_row_identity.dart';

/// Incoming or outgoing friend request row backed by callable actions.
class FriendRequestRow extends StatelessWidget {
  const FriendRequestRow({
    required this.user,
    this.onAccept,
    this.onDecline,
    this.onCancel,
    this.outgoing = false,
    this.isActionInFlight = false,
    super.key,
  }) : assert(
         outgoing ? onCancel != null : onAccept != null && onDecline != null,
       );

  final FriendUserReadModel user;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;
  final bool outgoing;
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
              FriendRowBadge(user: user),
              const SizedBox(width: 12),
              Expanded(child: FriendRowIdentity(user: user)),
              const SizedBox(width: 10),
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
              else if (outgoing)
                _RequestPill(
                  actionKey: 'friends-cancel-action-${user.userId}',
                  semanticLabel: 'Cancel ${user.displayName}',
                  label: 'Cancel',
                  onTap: onCancel,
                )
              else ...[
                _RequestPill(
                  actionKey: 'friends-accept-action-${user.userId}',
                  semanticLabel: 'Accept ${user.displayName}',
                  label: 'Accept',
                  onTap: onAccept,
                  primary: true,
                  horizontalPadding: 14,
                ),
                const SizedBox(width: 8),
                _RequestPill(
                  actionKey: 'friends-decline-action-${user.userId}',
                  semanticLabel: 'Decline ${user.displayName}',
                  label: 'Decline',
                  onTap: onDecline,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestPill extends StatelessWidget {
  const _RequestPill({
    required this.actionKey,
    required this.semanticLabel,
    required this.label,
    required this.onTap,
    this.primary = false,
    this.horizontalPadding = 12,
  });

  final String actionKey;
  final String semanticLabel;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return RuniacTappableSurface(
      key: ValueKey(actionKey),
      semanticLabel: semanticLabel,
      onTap: onTap,
      height: 44,
      alignment: Alignment.center,
      borderRadius: BorderRadius.circular(999),
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 9),
      decoration: BoxDecoration(
        color: primary ? RuniacColors.primaryBlue : RuniacColors.white,
        borderRadius: BorderRadius.circular(999),
        border: primary ? null : Border.all(color: RuniacColors.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: primary ? RuniacColors.white : RuniacColors.textSecondary,
          fontSize: 12.5,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
