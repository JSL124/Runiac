part of 'feed_comment_sheet.dart';

/// The layout half of [FeedCommentSheet], split off as a `part` to keep the
/// state class focused on behaviour.
///
/// The awkward part of a comment sheet is the keyboard: it is a draggable
/// scrollable sheet whose bottom padding tracks `viewInsets`, so the composer
/// stays above the keyboard without the list jumping as it opens.
extension _FeedCommentSheetLayout on _FeedCommentSheetState {
  Widget buildCommentSheetLayout(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height,
    child: AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        controller: widget.sheetController,
        expand: false,
        minChildSize: .32,
        initialChildSize: .72,
        maxChildSize: .94,
        shouldCloseOnMinExtent: false,
        builder: (context, scrollController) => _body(scrollController),
      ),
    ),
  );

  Widget _body(ScrollController scrollController) => Material(
    color: RuniacColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    clipBehavior: Clip.antiAlias,
    child: SafeArea(
      top: false,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: RuniacColors.cardBorder,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          const Text('Comments', style: YouTextStyles.cardTitle),
          const SizedBox(height: 12),
          const Divider(height: 1, color: RuniacColors.border),
          if (_isOffline)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                'Comments are read-only while offline.',
                style: YouTextStyles.smallBody,
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: buildCommentList(scrollController),
            ),
          ),
          const Divider(height: 1, color: RuniacColors.border),
          _composer(),
        ],
      ),
    ),
  );

  Widget _composer() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_editingCommentId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: RuniacColors.primaryBlue,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Editing comment',
                    style: YouTextStyles.smallStrong,
                  ),
                ),
                IconButton(
                  key: const ValueKey('feed-comment-cancel-edit'),
                  tooltip: 'Cancel editing',
                  onPressed: _isSubmitting ? null : _cancelEdit,
                  icon: const Icon(Icons.close, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        if (_validationError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _validationError!,
              style: const TextStyle(
                color: RuniacColors.errorRed,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: ValueKey(
                  'feed-comment-input-${widget._source.post.postId}',
                ),
                controller: _controller,
                focusNode: _focusNode,
                enabled: !_isOffline && !_isSubmitting,
                minLines: 1,
                maxLines: 4,
                buildCounter:
                    (
                      _, {
                      required currentLength,
                      required isFocused,
                      maxLength,
                    }) => null,
                onChanged: _commentTextChanged,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: RuniacColors.innerTileSurface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  hintText: 'Join the conversation...',
                  hintStyle: YouTextStyles.smallBody,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: RuniacColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(
                      color: RuniacColors.primaryBlue,
                      width: 1.5,
                    ),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: RuniacColors.border),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: ValueKey(
                'feed-comment-submit-${widget._source.post.postId}',
              ),
              tooltip: _editingCommentId == null
                  ? 'Post comment'
                  : 'Save edited comment',
              onPressed: _canSubmit ? _submit : null,
              icon: Icon(_editingCommentId == null ? Icons.send : Icons.check),
              style: const ButtonStyle(
                minimumSize: WidgetStatePropertyAll(Size.square(48)),
                maximumSize: WidgetStatePropertyAll(Size.square(48)),
                padding: WidgetStatePropertyAll(EdgeInsets.zero),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

enum FeedCommentOwnerAction { edit, delete }

Future<FeedCommentOwnerAction?> showFeedCommentOwnerActions(
  BuildContext context,
  FeedCommentReadModel comment,
) => showModalBottomSheet<FeedCommentOwnerAction>(
  context: context,
  showDragHandle: true,
  builder: (context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Comment options', style: YouTextStyles.bodyStrong),
          const SizedBox(height: 8),
          ListTile(
            key: ValueKey('feed-comment-edit-${comment.commentId}'),
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () => Navigator.pop(context, FeedCommentOwnerAction.edit),
          ),
          ListTile(
            key: ValueKey('feed-comment-delete-${comment.commentId}'),
            leading: const Icon(
              Icons.delete_outline,
              color: RuniacColors.errorRed,
            ),
            title: const Text(
              'Delete',
              style: TextStyle(color: RuniacColors.errorRed),
            ),
            onTap: () => Navigator.pop(context, FeedCommentOwnerAction.delete),
          ),
        ],
      ),
    ),
  ),
);

Future<bool> confirmFeedCommentDelete(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Delete comment?', style: YouTextStyles.bodyStrong),
              const SizedBox(height: 8),
              const Text(
                'This comment will be removed from this post.',
                style: YouTextStyles.smallBody,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      style: const ButtonStyle(
                        backgroundColor: WidgetStatePropertyAll(
                          RuniacColors.errorRed,
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ) ??
    false;
