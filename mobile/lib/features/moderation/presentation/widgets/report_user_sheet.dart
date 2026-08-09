import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../../core/assets/runiac_assets.dart';
import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../../../core/widgets/runiac_sheet_primitives.dart';
import '../../../../core/widgets/runiac_sheet_scaffold.dart';
import '../../../you/presentation/widgets/you_surface_primitives.dart';
import '../../domain/models/report_user_reason.dart';

/// Opens [ReportUserSheet] as a modal bottom sheet, matching how the feed's
/// report-a-post affordance is launched in feed_sheets.dart.
Future<void> showReportUserSheet(
  BuildContext context, {
  required String targetDisplayName,
  required Future<void> Function(ReportUserReason reason, String description)
  onSubmit,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => ReportUserSheet(
      targetDisplayName: targetDisplayName,
      onSubmit: onSubmit,
    ),
  );
}

/// Bottom sheet for reporting another runner from their profile or from a
/// Friends row. Reuses the submit / submitting / terminal-state idiom
/// already established by `FeedPostOptionsSheet` in feed_sheets.dart.
///
/// Display-only: no XP, streak, level, rank, leaderboard score, or
/// subscription value is read, calculated, or written here — [onSubmit]
/// writes only the fixed `reports` fields the security rules allow (see
/// `report_user_writer.dart`).
///
/// The "Report received" success panel is shown whether this is the first
/// report of this target or a duplicate: the Firestore rules silently deny a
/// duplicate create, and [onSubmit] is expected to silently swallow that
/// specific denial, so this widget cannot tell the two cases apart and must
/// not try to.
class ReportUserSheet extends StatefulWidget {
  const ReportUserSheet({
    required this.targetDisplayName,
    required this.onSubmit,
    super.key,
  });

  final String targetDisplayName;
  final Future<void> Function(ReportUserReason reason, String description)
  onSubmit;

  @override
  State<ReportUserSheet> createState() => _ReportUserSheetState();
}

class _ReportUserSheetState extends State<ReportUserSheet> {
  ReportUserReason _reason = ReportUserReason.harassmentOrAbuse;
  final _descriptionController = TextEditingController();
  var _isSubmitting = false;
  var _submitted = false;
  String? _error;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_reason, _descriptionController.text.trim());
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitted = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Report could not be sent. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return const RuniacSheetScaffold(
        title: 'Report received',
        child: _ReportReceivedPanel(),
      );
    }
    return RuniacSheetScaffold(
      title: 'Report ${widget.targetDisplayName}',
      subtitle:
          "Your report is private — ${widget.targetDisplayName} won't be told",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final reason in ReportUserReason.values)
            _ReasonRow(
              reason: reason,
              selected: reason == _reason,
              onTap: _isSubmitting
                  ? null
                  : () => setState(() => _reason = reason),
            ),
          TextField(
            key: const Key('report-user-description-field'),
            controller: _descriptionController,
            enabled: !_isSubmitting,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Additional details (optional)',
              filled: true,
              fillColor: RuniacColors.white,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(youInnerRadius),
                borderSide: const BorderSide(color: RuniacColors.cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(youInnerRadius),
                borderSide: const BorderSide(color: RuniacColors.cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(youInnerRadius),
                borderSide: const BorderSide(
                  color: RuniacColors.primaryBlue,
                  width: 1.5,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            RuniacSheetErrorBanner(message: _error!),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: RuniacColors.primaryBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: _isSubmitting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              RuniacColors.white,
                            ),
                          ),
                        ),
                        SizedBox(width: 10),
                        Text('Reporting…'),
                      ],
                    )
                  : const Text('Report'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One selectable reason row in the reason picker.
class _ReasonRow extends StatelessWidget {
  const _ReasonRow({
    required this.reason,
    required this.selected,
    required this.onTap,
  });

  final ReportUserReason reason;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: RuniacTappableSurface(
        key: ValueKey('report-user-reason-${reason.name}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(youInnerRadius),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? RuniacColors.sectionSurfaceStrong
              : RuniacColors.white,
          borderRadius: BorderRadius.circular(youInnerRadius),
          border: Border.all(
            color: selected
                ? RuniacColors.primaryBlue
                : RuniacColors.cardBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected
                  ? RuniacColors.primaryBlue
                  : RuniacColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(reason.label, style: YouTextStyles.bodyStrong),
            ),
          ],
        ),
      ),
    );
  }
}

/// Terminal-state panel shown once [ReportUserSheet]'s `onSubmit` completes,
/// whether that's a fresh report or a silently-swallowed duplicate.
///
/// The success copy lives on the enclosing [RuniacSheetScaffold]'s title —
/// this panel only supplies the check animation, supporting body copy, and
/// the dismiss action — so "Report received" appears exactly once in the
/// widget tree.
class _ReportReceivedPanel extends StatelessWidget {
  const _ReportReceivedPanel();

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 96,
          height: 96,
          child: reduceMotion
              ? const Icon(
                  Icons.check_circle_rounded,
                  size: 72,
                  color: RuniacColors.successGreen,
                )
              : Lottie.asset(
                  RuniacAssets.successCheckLottie,
                  repeat: false,
                  errorBuilder: (context, error, stackTrace) {
                    return const Icon(
                      Icons.check_circle_rounded,
                      size: 72,
                      color: RuniacColors.successGreen,
                    );
                  },
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
