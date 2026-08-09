import '../../domain/models/feed_display_models.dart';

List<FeedCommentReadModel> sessionCommentModels({
  required List<String> comments,
  required String authorUserId,
  FeedAuthorProfileSnapshot? authorProfile,
}) => List.generate(
  comments.length,
  (index) => FeedCommentReadModel(
    commentId: 'session-$index',
    authorUserId: authorUserId,
    authorDisplayName: authorProfile?.displayName ?? 'You',
    authorAvatarInitials: authorProfile?.avatarInitials ?? 'YO',
    authorAvatarUrl: authorProfile?.avatarUrl ?? '',
    authorLevelLabel: authorProfile?.levelLabel ?? '',
    body: comments[index],
    createdAt: DateTime.fromMillisecondsSinceEpoch(index),
  ),
).reversed.toList(growable: false);

FeedCommentCursor? lastCommentCursor(List<FeedCommentReadModel> comments) =>
    comments.isEmpty
    ? null
    : FeedCommentCursor(
        createdAt: comments.last.createdAt,
        commentId: comments.last.commentId,
      );

List<FeedCommentReadModel> replaceCommentBody({
  required List<FeedCommentReadModel> comments,
  required String commentId,
  required String body,
}) => comments
    .map(
      (item) => item.commentId == commentId ? item.copyWith(body: body) : item,
    )
    .toList();

List<FeedCommentReadModel> withoutComment({
  required List<FeedCommentReadModel> comments,
  required String commentId,
}) => comments.where((item) => item.commentId != commentId).toList();

String feedCommentAgeLabel(DateTime createdAt, DateTime now) {
  final age = now.toUtc().difference(createdAt.toUtc());
  if (age.isNegative || age.inMinutes < 1) return 'now';
  if (age.inHours < 1) return '${age.inMinutes}m';
  if (age.inDays < 1) return '${age.inHours}h';
  if (age.inDays < 7) return '${age.inDays}d';
  if (age.inDays < 28) return '${age.inDays ~/ 7}w';
  return '${age.inDays ~/ 28}mo';
}
