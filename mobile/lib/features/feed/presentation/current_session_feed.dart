import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../tutorial/domain/models/tutorial_step.dart';
import '../../tutorial/presentation/tutorial_anchor_registry.dart';
import '../data/static_feed_repository.dart';
import '../domain/models/feed_display_models.dart';
import '../domain/repositories/feed_repository.dart';
import 'current_session_feed_store.dart';
import 'feed_comment_intent_controller.dart';
import 'feed_timeline_screen_controller.dart';
import 'widgets/feed_header.dart';
import 'widgets/feed_post_list.dart';

export 'current_session_feed_store.dart';

class CurrentSessionFeed extends StatefulWidget {
  const CurrentSessionFeed({
    this.repository = const StaticFeedRepository(),
    this.viewerContext,
    this.currentAuthorProfile,
    this.commentIntent,
    super.key,
  });

  final FeedRepository repository;
  final FeedViewerContext? viewerContext;
  final FeedAuthorProfileSnapshot? currentAuthorProfile;

  /// Notification tap-through intent. `null` (previews/tests, and the
  /// default) means a tapped feed-engagement notification is never consumed
  /// here — the composition root supplies the shell-owned controller in
  /// production.
  final FeedCommentIntentController? commentIntent;

  @override
  State<CurrentSessionFeed> createState() => _CurrentSessionFeedState();
}

class _CurrentSessionFeedState extends State<CurrentSessionFeed> {
  late FeedTimelineScreenController _controller;
  CurrentSessionFeedStore? _sessionStore;
  bool _consumingCommentIntent = false;

  @override
  void initState() {
    super.initState();
    _replaceController();
    widget.commentIntent?.addListener(_maybeConsumePendingCommentIntent);
  }

  @override
  void didUpdateWidget(covariant CurrentSessionFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.commentIntent != widget.commentIntent) {
      oldWidget.commentIntent?.removeListener(
        _maybeConsumePendingCommentIntent,
      );
      widget.commentIntent?.addListener(_maybeConsumePendingCommentIntent);
    }
    if (oldWidget.repository != widget.repository ||
        oldWidget.viewerContext != widget.viewerContext) {
      _controller.removeListener(_rebuild);
      _controller.dispose();
      _replaceController();
    } else if (oldWidget.currentAuthorProfile != widget.currentAuthorProfile) {
      _controller.updateCurrentAuthorProfile(widget.currentAuthorProfile);
      _syncAuthorProfile();
      // A renamed viewer needs the whole timeline re-read, not just their own
      // header: every post stores the author's name frozen at publish time, so
      // the current name only arrives with a fresh load and its author
      // overlay. A level change alone is already handled in place and must not
      // pay for a reload.
      if (_identityChanged(
        oldWidget.currentAuthorProfile,
        widget.currentAuthorProfile,
      )) {
        unawaited(_controller.refresh());
      }
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextStore = CurrentSessionFeedScope.maybeOf(context);
    if (_sessionStore == nextStore) return;
    _sessionStore?.removeListener(_onSessionChanged);
    _sessionStore = nextStore;
    _controller.attachSession(nextStore);
    _syncAuthorProfile();
    _sessionStore?.addListener(_onSessionChanged);
  }

  @override
  void dispose() {
    widget.commentIntent?.removeListener(_maybeConsumePendingCommentIntent);
    _sessionStore?.removeListener(_onSessionChanged);
    _controller
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  void _replaceController() {
    _controller = FeedTimelineScreenController(
      widget.repository,
      widget.viewerContext,
      widget.currentAuthorProfile,
      widget.commentIntent,
    )..addListener(_rebuild);
    _controller.attachSession(_sessionStore);
    _controller.refresh();
  }

  void _syncAuthorProfile() {
    final profile = widget.currentAuthorProfile;
    final store = _sessionStore;
    if (profile == null || store == null) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !identical(_sessionStore, store) ||
          widget.currentAuthorProfile != profile) {
        return;
      }
      store.updateAuthorProfile(profile);
    });
  }

  static bool _identityChanged(
    FeedAuthorProfileSnapshot? previous,
    FeedAuthorProfileSnapshot? next,
  ) {
    if (previous == null || next == null) return false;
    return previous.userId == next.userId &&
        (previous.displayName != next.displayName ||
            previous.avatarInitials != next.avatarInitials ||
            previous.avatarUrl != next.avatarUrl);
  }

  void _rebuild() {
    if (mounted) setState(() {});
    // The timeline's own load/refresh completing is the other moment (besides
    // a fresh notification request) a pending intent can now be resolvable —
    // tab 1 mounts lazily and its first load races the intent arriving.
    _maybeConsumePendingCommentIntent();
  }

  /// Consumes a pending feed-engagement notification intent once the
  /// timeline has loaded and nothing else is already mid-open. Idempotent:
  /// the intent is cleared as soon as a consume begins, so neither this
  /// listener nor the controller rebuild path it also runs from can ever
  /// double-fire it.
  void _maybeConsumePendingCommentIntent() {
    final intent = widget.commentIntent;
    final postId = intent?.pendingPostId;
    if (postId == null ||
        !mounted ||
        _consumingCommentIntent ||
        !_controller.hasLoaded ||
        _controller.commentSheetOpen) {
      return;
    }
    _consumingCommentIntent = true;
    intent!.clear();
    unawaited(_consumeCommentIntent(postId));
  }

  Future<void> _consumeCommentIntent(String postId) async {
    try {
      final outcome = await _controller.openCommentsForPostId(
        context,
        postId,
      );
      if (!mounted) return;
      final message = switch (outcome) {
        FeedCommentOpenOutcome.opened => null,
        FeedCommentOpenOutcome.notFound =>
          'That post is no longer in your feed.',
        FeedCommentOpenOutcome.unavailable =>
          'Comments are unavailable right now.',
      };
      if (message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      _consumingCommentIntent = false;
    }
  }

  void _onSessionChanged() {
    if (_controller.clearForOwnerChange() && _controller.commentSheetOpen) {
      Navigator.of(context).pop();
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: RuniacColors.background,
    child: SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: FeedHeader(),
          ),
          Expanded(
            child: TutorialAnchor(
              id: TutorialAnchorId.feedPostList,
              child: RefreshIndicator(
                semanticsLabel: 'Pull to refresh feed',
                onRefresh: _controller.refresh,
                child: FeedPostList(controller: _controller),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
