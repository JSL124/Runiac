import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';
import '../../features/you/presentation/widgets/you_surface_primitives.dart';
import 'runiac_buttons.dart';
import 'runiac_sheet_primitives.dart';
import 'runiac_sheet_scaffold.dart';

/// Runiac's house confirmation **bottom sheet**: the shared sheet chrome
/// ([RuniacSheetScaffold]) over a tinted icon medallion, the question, and a
/// full-width confirm button above the standard cancel row.
///
/// The sibling of [showRuniacConfirmDialog] in runiac_confirm_dialog.dart —
/// use this one where the confirmation follows a sheet-shaped affordance
/// (a row or CTA inside a scrolling screen) so the answer rises from the same
/// edge the app's other sheets do.
Future<bool> showRuniacConfirmSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  RuniacButtonTone confirmTone = RuniacButtonTone.orange,
  Key? confirmKey,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    elevation: 0,
    builder: (_) => _RuniacConfirmSheet(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      icon: icon,
      confirmTone: confirmTone,
      confirmKey: confirmKey,
    ),
  );
  return result == true;
}

class _RuniacConfirmSheet extends StatelessWidget {
  const _RuniacConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
    required this.confirmTone,
    required this.confirmKey,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final RuniacButtonTone confirmTone;
  final Key? confirmKey;

  @override
  Widget build(BuildContext context) {
    final tint = switch (confirmTone) {
      RuniacButtonTone.blue => RuniacColors.primaryBlue,
      RuniacButtonTone.orange => RuniacColors.accentOrange,
    };

    // The scaffold's own title slot is left-aligned for action sheets; a
    // confirmation reads better centred under its medallion, so the heading
    // is composed in the child instead.
    return RuniacSheetScaffold(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.10),
                shape: BoxShape.circle,
                border: Border.all(color: tint.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, color: tint, size: 28),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: YouTextStyles.cardTitle,
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 13,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            key: confirmKey,
            onPressed: () => Navigator.of(context).pop<bool>(true),
            style: RuniacButtonStyles.primary(
              tone: confirmTone,
              minimumSize: const Size(0, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text(confirmLabel),
          ),
          const SizedBox(height: 4),
          RuniacSheetCancelButton(
            label: cancelLabel,
            onPressed: () => Navigator.of(context).pop<bool>(false),
          ),
        ],
      ),
    );
  }
}
