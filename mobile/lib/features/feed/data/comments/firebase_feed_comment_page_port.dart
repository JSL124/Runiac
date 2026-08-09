import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/feed_display_models.dart';
import '../firebase_feed_repository/feed_data_port.dart';

/// Bounded Firestore adapter for flat Feed comments.
class FirebaseFeedCommentPagePort {
  const FirebaseFeedCommentPagePort._();

  static Future<FeedCommentDocumentPage> load({
    required FirebaseFirestore firestore,
    required String postId,
    FeedCommentCursor? startAfter,
  }) async {
    Query<Map<String, Object?>> query = firestore
        .collection('feedPosts')
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(20);
    if (startAfter != null) {
      query = query.startAfter(<Object>[
        Timestamp.fromDate(startAfter.createdAt),
        startAfter.commentId,
      ]);
    }
    final snapshot = await query.get();
    final comments = snapshot.docs.map(_map).toList(growable: false);
    final last = comments.isEmpty ? null : comments.last;
    return FeedCommentDocumentPage(
      comments: comments,
      fromCache: snapshot.metadata.isFromCache,
      nextCursor: last == null
          ? null
          : FeedCommentCursor(
              createdAt: last.createdAt,
              commentId: last.commentId,
            ),
    );
  }

  static FeedCommentDocument _map(
    DocumentSnapshot<Map<String, Object?>> document,
  ) {
    final data = document.data();
    final createdAt = data?['createdAt'];
    final authorUid = data?['authorUid'];
    final displayName = data?['authorDisplayName'];
    final avatarInitials = data?['authorAvatarInitials'];
    final levelLabel = data?['authorLevelLabel'];
    final body = data?['body'];
    if (createdAt is! Timestamp ||
        authorUid is! String ||
        displayName is! String ||
        avatarInitials is! String ||
        body is! String) {
      throw const FormatException('Feed comment document is invalid.');
    }
    return FeedCommentDocument(
      commentId: document.id,
      authorUid: authorUid,
      authorDisplayName: displayName,
      authorAvatarInitials: avatarInitials,
      authorLevelLabel: levelLabel is String ? levelLabel : '',
      body: body,
      createdAt: createdAt.toDate(),
    );
  }
}
