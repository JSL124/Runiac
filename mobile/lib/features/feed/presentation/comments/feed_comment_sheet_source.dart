part of 'feed_comment_sheet.dart';

/// Local fallback behavior for the non-repository Feed surface.
class FeedCommentFallback {
  const FeedCommentFallback({
    required this.comments,
    required this.onSubmitted,
  });

  final List<String> comments;
  final ValueChanged<String> onSubmitted;
}

sealed class _FeedCommentSheetSource {
  const _FeedCommentSheetSource(
    this.post,
    this.viewerUserId,
    this.currentAuthorProfile,
  );

  final FeedPostReadModel post;
  final String? viewerUserId;
  final FeedAuthorProfileSnapshot? currentAuthorProfile;
  FeedCommentsRepository? get repository;
  List<String> get sessionComments;
  ValueChanged<String>? get onSubmitted;
}

class _RepositoryFeedCommentSheetSource extends _FeedCommentSheetSource {
  const _RepositoryFeedCommentSheetSource(
    super.post,
    this.repository,
    super.viewerUserId,
    super.currentAuthorProfile,
  );

  @override
  final FeedCommentsRepository repository;
  @override
  List<String> get sessionComments => const <String>[];
  @override
  ValueChanged<String>? get onSubmitted => null;
}

class _FallbackFeedCommentSheetSource extends _FeedCommentSheetSource {
  const _FallbackFeedCommentSheetSource(
    super.post,
    super.viewerUserId,
    this.fallback,
    super.currentAuthorProfile,
  );

  final FeedCommentFallback fallback;
  @override
  FeedCommentsRepository? get repository => null;
  @override
  List<String> get sessionComments => fallback.comments;
  @override
  ValueChanged<String> get onSubmitted => fallback.onSubmitted;
}
