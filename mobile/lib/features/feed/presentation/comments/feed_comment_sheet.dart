import 'package:flutter/material.dart';

import '../../../../core/haptics/runiac_haptics_scope.dart';
import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_level_profile_badge.dart';
import '../../../profile/presentation/widgets/runner_profile_avatar_link.dart';
import '../../../you/presentation/widgets/you_surface_primitives.dart';
import '../../domain/models/feed_display_models.dart';
import '../../domain/repositories/feed_repository.dart';
import 'feed_comment_sheet_models.dart';

part 'feed_comment_list.dart';
part 'feed_comment_sheet_layout.dart';
part 'feed_comment_sheet_source.dart';

/// The comments sheet for a feed post.
///
/// Opened both from a post and from a comment notification. The notification
/// path may name a comment on a post that is no longer in the loaded page, so
/// the sheet resolves that post by a single direct read rather than paging the
/// feed until it appears — see the tap-through regression test.
///
/// A comment's author can edit or delete their own ([FeedCommentOwnerAction]);
/// anyone else can only report it.
class FeedCommentSheet extends StatefulWidget {
  const FeedCommentSheet._(this._source, [this.sheetController]);

  factory FeedCommentSheet.fromRepository(
    FeedPostReadModel post,
    FeedCommentsRepository repository,
    String? viewerUserId,
    FeedAuthorProfileSnapshot? currentAuthorProfile,
  ) => FeedCommentSheet._(
    _RepositoryFeedCommentSheetSource(
      post,
      repository,
      viewerUserId,
      currentAuthorProfile,
    ),
  );

  factory FeedCommentSheet.fromFallback(
    FeedPostReadModel post,
    String? viewerUserId,
    FeedCommentFallback fallback,
    FeedAuthorProfileSnapshot? currentAuthorProfile,
  ) => FeedCommentSheet._(
    _FallbackFeedCommentSheetSource(
      post,
      viewerUserId,
      fallback,
      currentAuthorProfile,
    ),
  );

  FeedCommentSheet controlledBy(DraggableScrollableController? controller) =>
      FeedCommentSheet._(_source, controller);

  final _FeedCommentSheetSource _source;
  final DraggableScrollableController? sheetController;

  @override
  State<FeedCommentSheet> createState() => _FeedCommentSheetState();
}

class _FeedCommentSheetState extends State<FeedCommentSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late List<FeedCommentReadModel> _comments = sessionCommentModels(
    comments: widget._source.sessionComments,
    authorUserId: widget._source.viewerUserId ?? 'runner-current',
    authorProfile: widget._source.currentAuthorProfile,
  );
  FeedCommentCursor? _nextCursor;
  var _isLoading = false, _isLoadingMore = false, _exhausted = false;
  var _source = FeedTimelineSource.server;
  String? _loadError, _validationError, _editingCommentId;
  var _isSubmitting = false;

  bool get _isOffline => _source == FeedTimelineSource.cachedOffline;
  bool get _canSubmit =>
      !_isOffline &&
      !_isLoading &&
      !_isSubmitting &&
      _controller.text.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (widget._source.repository != null) {
      _loadInitial();
    } else {
      _exhausted = true;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final repository = widget._source.repository;
    if (!mounted || repository == null) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final page = await repository.loadComments(
        postId: widget._source.post.postId,
      );
      if (!mounted) return;
      setState(() {
        _comments = page.comments;
        _source = page.source;
        _exhausted = page.exhausted;
        _nextCursor = lastCommentCursor(page.comments);
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Comments could not load.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    final repository = widget._source.repository;
    if (repository == null ||
        _nextCursor == null ||
        _exhausted ||
        _isLoading ||
        _isLoadingMore) {
      return;
    }
    setState(() => _isLoadingMore = true);
    try {
      final page = await repository.loadComments(
        postId: widget._source.post.postId,
        startAfter: _nextCursor,
      );
      if (!mounted) return;
      final ids = _comments.map((item) => item.commentId).toSet();
      setState(() {
        _comments = [
          ..._comments,
          ...page.comments.where((item) => ids.add(item.commentId)),
        ];
        _source = page.source;
        _exhausted = page.exhausted;
        _nextCursor = lastCommentCursor(page.comments);
      });
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Comments could not load.');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _submit() async {
    if (!mounted) return;
    final body = _controller.text.trim();
    if (body.isEmpty || body.length > 500) {
      RuniacHapticsScope.maybeOf(context)?.error();
      setState(() => _validationError = 'Write 1 to 500 characters.');
      return;
    }
    if (_isOffline || _isSubmitting) return;
    final repository = widget._source.repository;
    final editingId = _editingCommentId;
    setState(() => _isSubmitting = true);
    try {
      if (repository == null) {
        widget._source.onSubmitted?.call(body);
        setState(
          () => _comments = [
            FeedCommentReadModel(
              commentId: 'session-${_comments.length}',
              authorUserId: widget._source.viewerUserId ?? 'runner-current',
              authorDisplayName:
                  widget._source.currentAuthorProfile?.displayName ?? 'You',
              authorAvatarInitials:
                  widget._source.currentAuthorProfile?.avatarInitials ?? 'YO',
              authorAvatarUrl:
                  widget._source.currentAuthorProfile?.avatarUrl ?? '',
              authorLevelLabel:
                  widget._source.currentAuthorProfile?.levelLabel ?? '',
              body: body,
              createdAt: DateTime.now(),
            ),
            ..._comments,
          ],
        );
      } else if (editingId == null) {
        await repository.createComment(
          FeedCommentMutation(
            postId: widget._source.post.postId,
            commentId: null,
            body: body,
          ),
        );
        if (!mounted) return;
        await _loadInitial();
      } else {
        await repository.updateComment(
          FeedCommentMutation(
            postId: widget._source.post.postId,
            commentId: editingId,
            body: body,
          ),
        );
        if (mounted) {
          setState(
            () => _comments = replaceCommentBody(
              comments: _comments,
              commentId: editingId,
              body: body,
            ),
          );
        }
      }
      if (!mounted) return;
      // The comment is posted (or edited) at this point, so confirm it in the
      // hand the same way the like tap does.
      RuniacHapticsScope.maybeOf(context)?.impactLight();
      setState(() {
        _controller.clear();
        _editingCommentId = null;
        _validationError = null;
      });
    } catch (_) {
      if (mounted) {
        RuniacHapticsScope.maybeOf(context)?.error();
        setState(() => _validationError = 'Comment could not save.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _beginEdit(FeedCommentReadModel comment) {
    _controller.text = comment.body;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    setState(() {
      _editingCommentId = comment.commentId;
      _validationError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  void _cancelEdit() {
    _controller.clear();
    setState(() {
      _editingCommentId = null;
      _validationError = null;
    });
    _focusNode.unfocus();
  }

  Future<void> _showOwnerActions(FeedCommentReadModel comment) async {
    final action = await showFeedCommentOwnerActions(context, comment);
    if (!mounted || action == null) return;
    switch (action) {
      case FeedCommentOwnerAction.edit:
        _beginEdit(comment);
      case FeedCommentOwnerAction.delete:
        await _confirmDelete(comment);
    }
  }

  void _commentTextChanged(String _) => setState(() => _validationError = null);

  Future<void> _confirmDelete(FeedCommentReadModel comment) async {
    final confirmed = await confirmFeedCommentDelete(context);
    if (!mounted) return;
    if (!confirmed || _isOffline || _isSubmitting) {
      return;
    }
    try {
      setState(() => _isSubmitting = true);
      await widget._source.repository?.deleteComment(
        postId: widget._source.post.postId,
        commentId: comment.commentId,
      );
      if (mounted) {
        setState(() {
          _comments = withoutComment(
            comments: _comments,
            commentId: comment.commentId,
          );
          if (_editingCommentId == comment.commentId) {
            _editingCommentId = null;
            _controller.clear();
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _validationError = 'Comment could not delete.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => buildCommentSheetLayout(context);
}
