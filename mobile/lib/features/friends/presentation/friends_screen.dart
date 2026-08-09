import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../auth/domain/runiac_auth_service.dart';
import '../../moderation/data/report_user_writer.dart';
import '../../moderation/presentation/widgets/report_user_sheet.dart';
import '../../you/presentation/widgets/you_segmented_control.dart';
import '../data/static_friends_repository.dart';
import '../domain/models/friends_read_model.dart';
import '../domain/repositories/friends_repository.dart';
import 'friends_action_sheets.dart';
import 'friends_screen_controller.dart';
import 'widgets/friends_list_tabs.dart';
import 'widgets/friends_requests_tab.dart';
import 'widgets/friends_rows.dart';
import 'widgets/friends_search_tab.dart';

part 'friends_screen_actions.dart';

const List<String> _kFriendsTabLabels = [
  'Friends',
  'Search',
  'Requests',
  'Blocked',
];

/// Friends: the runner's list, incoming requests, and search.
///
/// Sectioned by a segmented control rather than tabs so the pending-request
/// count stays visible while browsing the list — a request the user never
/// notices is a request that never gets accepted.
///
/// Reporting a user is reachable from here and writes to the moderation queue
/// the admin console triages.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({
    required this.authRepository,
    required this.onBack,
    this.repository,
    super.key,
  });

  final RuniacAuthRepository authRepository;
  final FriendsRepository? repository;
  final VoidCallback onBack;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  late final TextEditingController _searchController;
  late FriendsScreenController _controller;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()..addListener(_onSearchChanged);
    _controller = _buildController();
  }

  @override
  void didUpdateWidget(covariant FriendsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authRepository != widget.authRepository) {
      _replaceController();
    }
    if (oldWidget.repository != widget.repository) {
      _replaceController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  FriendsScreenController _buildController() {
    return FriendsScreenController(
      authRepository: widget.authRepository,
      repository: widget.repository ?? StaticFriendsRepository(),
    );
  }

  void _replaceController() {
    final previous = _controller;
    _controller = _buildController();
    previous.dispose();
    setState(() {});
  }

  void _onSearchChanged() {
    _controller.onSearchTextChanged(_searchController.text);
  }

  Future<void> _submitSearch() async {
    await _controller.submitSearch(_searchController.text);
  }

  Future<void> _runMutation({
    required String actionKey,
    required FriendsMutationAction action,
  }) async {
    await _controller.runMutation(actionKey: actionKey, action: action);
  }

  Future<void> _retry() async {
    await _controller.retry();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: Column(
          children: [
            RuniacBackHeader(title: 'Friends', onBack: widget.onBack),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: YouSegmentedControl(
                labels: _kFriendsTabLabels,
                selected: _tabIndex,
                compact: true,
                onTap: (index) {
                  setState(() {
                    _tabIndex = index;
                  });
                },
              ),
            ),
            Expanded(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_controller.ownerUid == null) {
      return const FriendsEmptyState(
        title: 'Sign in to view friends',
        body: 'Your friend list is only available while you are signed in.',
      );
    }
    final overview = _controller.overview;
    if (overview == null && _controller.isLoading) {
      return const _FriendsLoadingState();
    }
    if (overview == null) {
      return FriendsErrorState(
        message:
            _controller.errorMessage ?? 'Friends are temporarily unavailable.',
        onRetry: _retry,
      );
    }
    return Column(
      children: [
        if (_controller.errorMessage != null)
          FriendsErrorBanner(
            message: _controller.errorMessage!,
            onRetry: _retry,
          ),
        Expanded(child: _buildTabBody(overview)),
      ],
    );
  }

  Widget _buildTabBody(FriendsOverviewReadModel overview) {
    return switch (_tabIndex) {
      1 => FriendsSearchTab(
        controller: _controller,
        searchController: _searchController,
        overview: overview,
        onSubmit: _submitSearch,
        onAdd: _sendRequest,
      ),
      2 => FriendsRequestsTab(
        controller: _controller,
        overview: overview,
        onAccept: (user) =>
            _respondToRequest(user, FriendRequestResponseAction.accept),
        onDecline: (user) =>
            _respondToRequest(user, FriendRequestResponseAction.decline),
        onCancel: _cancelRequest,
      ),
      3 => BlockedFriendsTab(
        users: overview.blockedUsers,
        isActionInFlight: (userId) =>
            _controller.isActionInFlight('unblock:$userId'),
        onUnblock: _confirmUnblock,
      ),
      _ => FriendsListTab(
        users: overview.friends,
        isActionInFlight: (userId) =>
            _controller.isActionInFlight('social:$userId'),
        onMore: _showFriendActions,
      ),
    };
  }
}

class _FriendsLoadingState extends StatelessWidget {
  const _FriendsLoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text(
            'Loading friends...',
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
