import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';

/// Runiac's house confirmation dialog: a tinted icon badge over a centred
/// question, with the two choices given equal weight as full-width buttons.
///
/// Shared rather than per-feature so a destructive confirmation looks the same
/// wherever it is asked — the Friends actions and the notification inbox both
/// come through here.
Future<bool> showRuniacConfirmDialog(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  IconData icon = Icons.help_outline_rounded,
  bool isDestructive = true,
  Key? confirmKey,
}) async {
  final result = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: title,
    barrierColor: RuniacColors.textPrimary.withValues(alpha: 0.38),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (dialogContext, _, _) {
      return _RuniacConfirmDialog(
        title: title,
        body: body,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        icon: icon,
        isDestructive: isDestructive,
        confirmKey: confirmKey,
      );
    },
    transitionBuilder: (context, animation, _, child) {
      // Settles in with a slight overshoot so the dialog arrives rather than
      // appears, matching the app's other entrance motion.
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.92, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
  return result == true;
}

class _RuniacConfirmDialog extends StatelessWidget {
  const _RuniacConfirmDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
    required this.isDestructive,
    required this.confirmKey,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String cancelLabel;
  final IconData icon;
  final bool isDestructive;
  final Key? confirmKey;

  @override
  Widget build(BuildContext context) {
    final tint = isDestructive
        ? RuniacColors.errorRed
        : RuniacColors.primaryBlue;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: RuniacColors.white,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: RuniacColors.cardBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33172033),
                blurRadius: 28,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
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
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
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
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(context).pop<bool>(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: RuniacColors.textSecondary,
                          backgroundColor: RuniacColors.white,
                          side: const BorderSide(color: RuniacColors.border),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        child: Text(cancelLabel),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        key: confirmKey,
                        onPressed: () => Navigator.of(context).pop<bool>(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: tint,
                          foregroundColor: RuniacColors.white,
                          minimumSize: const Size(0, 48),
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
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
