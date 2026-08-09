import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../domain/models/friends_read_model.dart';
import '../friends_screen_controller.dart';
import 'friends_rows.dart';

class FriendsRequestsTab extends StatelessWidget {
  const FriendsRequestsTab({
    required this.controller,
    required this.overview,
    required this.onAccept,
    required this.onDecline,
    required this.onCancel,
    super.key,
  });

  final FriendsScreenController controller;
  final FriendsOverviewReadModel overview;
  final ValueChanged<FriendUserReadModel> onAccept;
  final ValueChanged<FriendUserReadModel> onDecline;
  final ValueChanged<FriendUserReadModel> onCancel;

  @override
  Widget build(BuildContext context) {
    final incoming = overview.incomingRequests;
    final outgoing = overview.outgoingRequests;
    if (incoming.isEmpty && outgoing.isEmpty) {
      return const FriendsEmptyState(
        title: 'No pending requests',
        body: 'New friend requests will appear here.',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (incoming.isNotEmpty) ...[
          const _RequestSectionLabel(label: 'Incoming'),
          for (final user in incoming) ...[
            FriendRequestRow(
              user: user,
              onAccept: () => onAccept(user),
              onDecline: () => onDecline(user),
              isActionInFlight: controller.isActionInFlight(
                'request:${user.userId}',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
        if (outgoing.isNotEmpty) ...[
          const _RequestSectionLabel(label: 'Sent'),
          for (final user in outgoing) ...[
            FriendRequestRow(
              user: user,
              outgoing: true,
              onCancel: () => onCancel(user),
              isActionInFlight: controller.isActionInFlight(
                'request:${user.userId}',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _RequestSectionLabel extends StatelessWidget {
  const _RequestSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: RuniacColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
