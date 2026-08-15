import 'package:flutter/material.dart';

import '../../../tutorial/domain/models/tutorial_step.dart';
import '../../../tutorial/presentation/tutorial_anchor_registry.dart';
import '../../domain/models/feed_display_models.dart';
import '../feed_timeline_screen_controller.dart';
import 'feed_post_section.dart';
import 'feed_status_message.dart';

class FeedPostList extends StatelessWidget {
  const FeedPostList({required this.controller, super.key});

  final FeedTimelineScreenController controller;

  @override
  Widget build(BuildContext context) {
    final state = controller.timelineState;
    final error = state?.recoverableError?.message ?? controller.loadError;
    final posts = controller.posts;
    if (!controller.hasLoaded) {
      return _message(const CircularProgressIndicator());
    }
    if (posts.isEmpty && error != null) {
      return _error(error);
    }
    if (posts.isEmpty) {
      return _status(
        'No shared runs yet.',
        body: 'Runs shared by you and accepted friends will appear here.',
      );
    }
    final offline = !controller.mutationsEnabled;
    return ListView.builder(
      key: const ValueKey('feed-post-list'),
      controller: controller.scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: posts.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _FeedNotice(
            error: error,
            offline: offline,
            controller: controller,
          );
        }
        if (index <= posts.length) {
          final section = FeedPostSection(
            post: posts[index - 1],
            controller: controller,
          );
          // Only the very first post card (index == 1) is a tour anchor, so
          // the app tour has something concrete to spotlight on Feed. This
          // must never wrap any other index — a shared GlobalKey mounted
          // twice at once crashes the app.
          if (index == 1) {
            return TutorialAnchor(
              id: TutorialAnchorId.feedFirstPost,
              child: section,
            );
          }
          return section;
        }
        return _FeedFooter(state: state);
      },
    );
  }

  Widget _message(Widget child) => ListView(
    key: const ValueKey('feed-post-list'),
    controller: controller.scrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    children: [SizedBox(height: 280, child: Center(child: child))],
  );

  Widget _status(String title, {required String body}) => ListView(
    key: const ValueKey('feed-post-list'),
    controller: controller.scrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    children: [FeedStatusMessage(title: title, body: body)],
  );

  Widget _error(String message) => ListView(
    key: const ValueKey('feed-post-list'),
    controller: controller.scrollController,
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      FeedStatusMessage(
        title: message,
        body: 'Pull down or tap retry to load friends posts.',
        action: _FeedRetryButton(onRetry: controller.refresh),
      ),
    ],
  );
}

/// Retry affordance that shows the reload it starts.
///
/// The bare `OutlinedButton` this replaces called the very same `refresh`,
/// but a failed reload rebuilds the screen into the identical error state —
/// so every tap looked like a dead button, and a runner could not tell a
/// non-responsive control from a retry that ran and failed again. Pull to
/// refresh never had that problem because `RefreshIndicator` shows its own
/// spinner for exactly the same future.
class _FeedRetryButton extends StatefulWidget {
  const _FeedRetryButton({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  State<_FeedRetryButton> createState() => _FeedRetryButtonState();
}

class _FeedRetryButtonState extends State<_FeedRetryButton> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: _retrying ? null : _retry,
    child: _retrying
        ? const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Text('Retry'),
  );
}

class _FeedNotice extends StatelessWidget {
  const _FeedNotice({
    required this.error,
    required this.offline,
    required this.controller,
  });
  final String? error;
  final bool offline;
  final FeedTimelineScreenController controller;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (offline)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Offline — cached feed. Actions are disabled.'),
        ),
      if (error != null)
        TextButton(onPressed: controller.refresh, child: Text(error!)),
    ],
  );
}

class _FeedFooter extends StatelessWidget {
  const _FeedFooter({required this.state});
  final FeedTimelineState? state;
  @override
  Widget build(BuildContext context) => state?.exhausted == true
      ? const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text("You're all caught up.")),
        )
      : const SizedBox(height: 24);
}
