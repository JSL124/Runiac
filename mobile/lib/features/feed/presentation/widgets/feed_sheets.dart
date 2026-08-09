import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_sheet_primitives.dart';
import '../../../../core/widgets/runiac_sheet_scaffold.dart';
import '../../../you/presentation/widgets/you_surface_primitives.dart';

export '../comments/feed_comment_sheet.dart';
export '../comments/feed_comment_sheet_launcher.dart';

/// Presented the same way as the Friends "..." sheet — transparent barrier
/// surface and scroll-controlled — so [RuniacSheetScaffold] owns the rounded
/// card, the drag handle, and the home-indicator inset.
Future<void> showCurrentSessionFeedPostOptions(
  BuildContext context,
  FeedPostOptionsSheet sheet,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  elevation: 0,
  builder: (_) => sheet,
);

/// The Feed post "..." action sheet. Owners get Delete, everyone else gets
/// Report; both run through the same submit / submitting / terminal-state
/// idiom the sheet always had — this is presentation only.
class FeedPostOptionsSheet extends StatefulWidget {
  const FeedPostOptionsSheet._(this.showsOwnerMenu, this._action);
  factory FeedPostOptionsSheet.owner(Future<bool> Function() onDelete) =>
      FeedPostOptionsSheet._(true, onDelete);
  factory FeedPostOptionsSheet.reporter([Future<bool> Function()? onReport]) =>
      FeedPostOptionsSheet._(false, onReport);

  final bool showsOwnerMenu;
  final Future<bool> Function()? _action;

  @override
  State<FeedPostOptionsSheet> createState() => _FeedPostOptionsSheetState();
}

class _FeedPostOptionsSheetState extends State<FeedPostOptionsSheet> {
  var _reportSubmitted = false;
  var _isSubmitting = false;
  String? _error;

  Future<void> _submit(Future<bool> Function()? action) async {
    if (action == null) {
      setState(() => _reportSubmitted = true);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    final success = await action();
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _isSubmitting = false;
      _error = 'Post action could not finish.';
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_reportSubmitted) {
      // The terminal copy lives on the scaffold title, so it appears exactly
      // once in the tree.
      return const RuniacSheetScaffold(
        title: 'Report submitted',
        child: _ReportSubmittedPanel(),
      );
    }
    return RuniacSheetScaffold(
      title: 'Post options',
      subtitle: 'Choose an action',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.showsOwnerMenu)
            RuniacSheetActionTile(
              key: const ValueKey('feed-post-delete-action'),
              icon: Icons.delete_outline_rounded,
              tint: RuniacColors.errorRed,
              titleColor: RuniacColors.errorRed,
              title: _isSubmitting ? 'Deleting…' : 'Delete',
              caption: 'Remove this post from the Feed',
              onTap: _isSubmitting ? null : () => _submit(widget._action),
              trailing: _isSubmitting
                  ? const RuniacSheetTileSpinner(color: RuniacColors.errorRed)
                  : null,
            )
          else
            RuniacSheetActionTile(
              key: const ValueKey('feed-post-report-action'),
              icon: Icons.flag_rounded,
              title: _isSubmitting ? 'Reporting…' : 'Report',
              caption: 'Tell us what went wrong',
              onTap: _isSubmitting ? null : () => _submit(widget._action),
              trailing: _isSubmitting ? const RuniacSheetTileSpinner() : null,
            ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            RuniacSheetErrorBanner(message: _error!),
          ],
          const SizedBox(height: 4),
          RuniacSheetCancelButton(enabled: !_isSubmitting),
        ],
      ),
    );
  }
}

/// Terminal panel shown once a report has been handed off, matching the
/// moderation report sheet's "Report received" state.
class _ReportSubmittedPanel extends StatelessWidget {
  const _ReportSubmittedPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: RuniacColors.successGreen.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            size: 40,
            color: RuniacColors.successGreen,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "Thanks — we've received your report. Our team will review it "
          'shortly.',
          textAlign: TextAlign.center,
          style: YouTextStyles.body,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: RuniacColors.primaryBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text('Done'),
          ),
        ),
      ],
    );
  }
}
