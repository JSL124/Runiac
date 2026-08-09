import 'package:flutter/material.dart';

import '../../../../core/assets/runiac_assets.dart';
import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../domain/models/friends_read_model.dart';
import 'friend_row_identity.dart';

/// Display-only row for a friend or exact-search result.
class FriendUserRow extends StatelessWidget {
  const FriendUserRow({
    required this.user,
    this.onAdd,
    this.onMore,
    this.isPending = false,
    this.isActionInFlight = false,
    super.key,
  }) : assert(onAdd == null || onMore == null),
       assert(!isPending || onAdd == null);

  final FriendUserReadModel user;
  final VoidCallback? onAdd;
  final VoidCallback? onMore;
  final bool isPending;
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
              Expanded(child: FriendRowName(user: user)),
              if (isActionInFlight) ...[
                const SizedBox(width: 8),
                _UpdatingAction(user: user),
              ] else if (onMore != null) ...[
                const SizedBox(width: 8),
                _FriendMoreAction(user: user, onTap: onMore),
              ] else if (onAdd != null || isPending) ...[
                const SizedBox(width: 8),
                _FriendRequestAction(
                  user: user,
                  onAdd: onAdd,
                  isPending: isPending,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdatingAction extends StatelessWidget {
  const _UpdatingAction({required this.user});

  final FriendUserReadModel user;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Updating ${user.displayName}',
      enabled: false,
      child: const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      ),
    );
  }
}

class _FriendRequestAction extends StatelessWidget {
  const _FriendRequestAction({
    required this.user,
    required this.onAdd,
    required this.isPending,
  });

  final FriendUserReadModel user;
  final VoidCallback? onAdd;
  final bool isPending;

  @override
  Widget build(BuildContext context) {
    final icon = ImageIcon(
      AssetImage(
        isPending ? RuniacAssets.friendsPending : RuniacAssets.friendsAdd,
      ),
      color: RuniacColors.primaryBlue,
      size: 22,
    );
    if (isPending) {
      return Semantics(
        container: true,
        label: 'Pending ${user.displayName}',
        enabled: false,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: ExcludeSemantics(child: icon)),
        ),
      );
    }
    return RuniacTappableSurface(
      key: ValueKey('friends-add-action-${user.userId}'),
      semanticLabel: 'Add ${user.displayName}',
      onTap: onAdd,
      width: 44,
      height: 44,
      alignment: Alignment.center,
      borderRadius: BorderRadius.circular(999),
      child: ExcludeSemantics(child: icon),
    );
  }
}

class _FriendMoreAction extends StatelessWidget {
  const _FriendMoreAction({required this.user, required this.onTap});

  final FriendUserReadModel user;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RuniacTappableSurface(
      key: ValueKey('friends-more-action-${user.userId}'),
      semanticLabel: 'More actions for ${user.displayName}',
      onTap: onTap,
      width: 44,
      height: 44,
      alignment: Alignment.center,
      borderRadius: BorderRadius.circular(999),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: RuniacColors.primaryBlue.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: const ExcludeSemantics(
        child: Icon(
          Icons.more_horiz_rounded,
          color: RuniacColors.primaryBlue,
          size: 22,
        ),
      ),
    );
  }
}
