import 'package:flutter/foundation.dart';

/// Holds at most one pending "open this post's comment sheet" request.
///
/// A tapped feed-engagement notification requests a postId here; the Feed
/// tab consumes it (opening the comment sheet, or reporting why it could
/// not) the next time it is able to, then clears it. There is deliberately
/// no history: a second [request] before the first is consumed simply
/// replaces it.
class FeedCommentIntentController extends ChangeNotifier {
  String? _pendingPostId;

  /// The postId awaiting a comment-sheet open, or `null` when none is
  /// pending.
  String? get pendingPostId => _pendingPostId;

  /// Records a request to open the comment sheet for [postId].
  void request(String postId) {
    _pendingPostId = postId;
    notifyListeners();
  }

  /// Clears the pending request, if any. A no-op (and no notification) when
  /// nothing is pending.
  void clear() {
    if (_pendingPostId == null) {
      return;
    }
    _pendingPostId = null;
    notifyListeners();
  }
}
