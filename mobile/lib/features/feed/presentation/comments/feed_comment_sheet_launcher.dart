import 'package:flutter/material.dart';

import 'feed_comment_sheet.dart';

/// Opens the comment surface through the same route used by the Feed UI.
Future<void> showFeedCommentSheet({
  required BuildContext context,
  required FeedCommentSheet sheet,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (context) => sheet,
);
