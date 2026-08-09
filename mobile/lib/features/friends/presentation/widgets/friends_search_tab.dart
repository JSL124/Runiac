import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../domain/models/friends_read_model.dart';
import '../friends_screen_controller.dart';
import 'friends_rows.dart';

class FriendsSearchTab extends StatelessWidget {
  const FriendsSearchTab({
    required this.controller,
    required this.searchController,
    required this.overview,
    required this.onSubmit,
    required this.onAdd,
    super.key,
  });

  final FriendsScreenController controller;
  final TextEditingController searchController;
  final FriendsOverviewReadModel overview;
  final Future<void> Function() onSubmit;
  final ValueChanged<FriendUserReadModel> onAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Semantics(
            label: 'Search runners',
            textField: true,
            child: TextField(
              controller: searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                labelText: 'Search runners',
                hintText: 'Enter an exact nickname',
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: RuniacColors.textSecondary,
                ),
              ),
            ),
          ),
        ),
        if (controller.isSearchLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Expanded(
          child: _SearchResults(
            controller: controller,
            overview: overview,
            onAdd: onAdd,
          ),
        ),
      ],
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
    required this.controller,
    required this.overview,
    required this.onAdd,
  });

  final FriendsScreenController controller;
  final FriendsOverviewReadModel overview;
  final ValueChanged<FriendUserReadModel> onAdd;

  @override
  Widget build(BuildContext context) {
    final results = controller.searchResults;
    if (controller.submittedSearch == null || results == null) {
      return const FriendsEmptyState(
        title: 'Find runners',
        body: 'Enter an exact nickname, then press search.',
      );
    }
    if (results.isEmpty) {
      return const FriendsEmptyState(
        title: 'No runners found',
        body: 'No runner matched that nickname.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final user = results[index];
        final pending = controller.hasOutgoingRequest(user, overview);
        return FriendUserRow(
          user: user,
          isPending: pending,
          isActionInFlight: controller.isActionInFlight('send:${user.userId}'),
          onAdd: pending ? null : () => onAdd(user),
        );
      },
    );
  }
}
