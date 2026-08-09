import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';
import '../../features/you/presentation/widgets/you_surface_primitives.dart';
import 'runiac_bottom_sheet_handle.dart';

/// Shared chrome for Runiac modal bottom sheets: a drag handle, an optional
/// title and subtitle, and caller-supplied content, wrapped in the rounded,
/// elevated surface used across the app's sheets.
///
/// [title] is omitted by sheets that compose their own heading in [child]
/// (the confirmation sheet centres its heading under an icon medallion).
///
/// This renders content only — callers own presentation (e.g. via
/// `showModalBottomSheet`) and sizing. Used by the Friends actions sheet
/// and the moderation `ReportUserSheet`.
class RuniacSheetScaffold extends StatelessWidget {
  const RuniacSheetScaffold({
    super.key,
    this.title,
    this.subtitle,
    required this.child,
  });

  final String? title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // The SafeArea sits *inside* the decoration so the sheet surface reaches
    // the physical bottom edge — wrapping the DecoratedBox instead would
    // carve the home-indicator inset out of the background and let the
    // barrier show through beneath the sheet.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RuniacColors.sectionSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x292F51C8),
            blurRadius: 40,
            offset: Offset(0, -14),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          // The SafeArea above already contributes the home-indicator inset,
          // so only the keyboard inset is added here.
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            8 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: RuniacBottomSheetHandle(
                  width: 40,
                  height: 5,
                  color: RuniacColors.primaryBlue.withValues(alpha: 0.18),
                  borderRadius: 99,
                ),
              ),
              const SizedBox(height: 14),
              if (title != null) Text(title!, style: YouTextStyles.cardTitle),
              if (subtitle != null) ...[
                if (title != null) const SizedBox(height: 4),
                Text(subtitle!, style: YouTextStyles.body),
              ],
              if (title != null || subtitle != null)
                const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
