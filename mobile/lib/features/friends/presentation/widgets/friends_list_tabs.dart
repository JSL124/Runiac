import 'package:flutter/material.dart';

import '../../domain/models/friends_read_model.dart';
import 'friends_rows.dart';

class FriendsListTab extends StatelessWidget {
  const FriendsListTab({
    required this.users,
    required this.isActionInFlight,
    required this.onMore,
    super.key,
  });

  final List<FriendUserReadModel> users;
  final bool Function(String userId) isActionInFlight;
  final ValueChanged<FriendUserReadModel> onMore;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const FriendsEmptyState(
        title: 'No friends yet',
        body: 'Runners you connect with will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = users[index];
        return FriendUserRow(
          user: user,
          onMore: () => onMore(user),
          isActionInFlight: isActionInFlight(user.userId),
        );
      },
    );
  }
}

class BlockedFriendsTab extends StatelessWidget {
  const BlockedFriendsTab({
    required this.users,
    required this.isActionInFlight,
    required this.onUnblock,
    super.key,
  });

  final List<FriendUserReadModel> users;
  final bool Function(String userId) isActionInFlight;
  final ValueChanged<FriendUserReadModel> onUnblock;

  @override
  Widget build(BuildContext context) {
    if (users.isEmpty) {
      return const FriendsEmptyState(
        title: 'No blocked runners',
        body: 'Runners you block will appear here.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: users.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = users[index];
        return BlockedUserRow(
          user: user,
          isActionInFlight: isActionInFlight(user.userId),
          onUnblock: () => onUnblock(user),
        );
      },
    );
  }
}
