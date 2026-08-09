import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../../../core/widgets/runiac_section_header.dart';

/// The shared card, header and divider widgets every You-tab surface is built
/// from.
///
/// Collected here so the tab and the screens it pushes (activity history, plan
/// detail) stay visually identical without copying padding and radii between
/// files. Add a new You surface by composing these rather than styling a fresh
/// `Container`.
class RuniacAccentStrip extends StatelessWidget {
  const RuniacAccentStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: RuniacColors.primaryBlue,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 34,
          height: 4,
          decoration: BoxDecoration(
            color: RuniacColors.accentOrange,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class YouHeaderAccentStrip extends StatelessWidget {
  const YouHeaderAccentStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 5,
          decoration: BoxDecoration(
            color: RuniacColors.primaryBlue,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 18,
          height: 5,
          decoration: BoxDecoration(
            color: RuniacColors.accentOrange,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class YouCardHeader extends StatelessWidget {
  const YouCardHeader(
    this.icon,
    this.label, {
    this.accent = false,
    this.iconSize = 18,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool accent;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return RuniacSectionHeader(
      title: label,
      leading: Icon(
        icon,
        size: iconSize,
        color: accent ? RuniacColors.accentOrange : RuniacColors.primaryBlue,
      ),
      titleStyle: YouTextStyles.cardTitle,
    );
  }
}

class YouDashboardCard extends StatelessWidget {
  const YouDashboardCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: RuniacColors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(youCardRadius),
        side: const BorderSide(color: RuniacColors.cardBorder),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}

class YouDividerSection extends StatelessWidget {
  const YouDividerSection({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _YouSectionDivider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: child,
        ),
        const _YouSectionDivider(),
      ],
    );
  }
}

class _YouSectionDivider extends StatelessWidget {
  const _YouSectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: RuniacColors.border);
  }
}

class StaticPlanAction extends StatelessWidget {
  const StaticPlanAction(this.label, {this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return RuniacTappableSurface(
      onTap: onTap,
      semanticsButton: onTap != null,
      borderRadius: BorderRadius.circular(youInnerRadius),
      height: 44,
      alignment: Alignment.center,
      decoration: youCardLikeDecoration,
      child: Text(label, style: YouTextStyles.button),
    );
  }
}

Widget planBadge(String label) {
  return Container(
    height: 30,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: youPillDecoration(const Color(0xFFF7FAFF)),
    child: Text(label, style: YouTextStyles.smallStrong),
  );
}

BoxDecoration youPillDecoration(Color color) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(999),
    border: Border.all(color: RuniacColors.border),
  );
}

final youCardLikeDecoration = BoxDecoration(
  color: RuniacColors.white,
  borderRadius: BorderRadius.circular(youInnerRadius),
  border: Border.all(color: RuniacColors.cardBorder),
);

final youSoftIconDecoration = BoxDecoration(
  color: RuniacColors.innerTileSurface,
  borderRadius: BorderRadius.circular(youInnerRadius),
  border: Border.all(color: RuniacColors.border),
);

const youCardRadius = 20.0;
const youInnerRadius = 16.0;

abstract final class YouTextStyles {
  static const cardTitle = TextStyle(
    color: RuniacColors.textPrimary,
    fontSize: 19,
    fontWeight: FontWeight.w800,
    height: 1.08,
  );

  static const headerTitle = TextStyle(
    color: RuniacColors.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w900,
  );

  static const section = TextStyle(
    color: RuniacColors.textPrimary,
    fontSize: 24,
    fontWeight: FontWeight.w900,
  );

  static const seeAll = TextStyle(
    color: Color(0xFF8EA2EA),
    fontSize: 15,
    fontWeight: FontWeight.w800,
  );

  static const heroNumber = TextStyle(
    color: RuniacColors.textPrimary,
    fontSize: 34,
    fontWeight: FontWeight.w900,
    height: 1,
  );

  static const largeValue = TextStyle(
    color: RuniacColors.textPrimary,
    fontSize: 22,
    fontWeight: FontWeight.w900,
  );

  static const planPercent = TextStyle(
    color: RuniacColors.primaryBlue,
    fontSize: 22,
    fontWeight: FontWeight.w900,
  );

  static const button = TextStyle(
    color: RuniacColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w900,
  );

  static const labelStrong = TextStyle(
    color: RuniacColors.textSecondary,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  static const smallStrong = TextStyle(
    color: RuniacColors.textSecondary,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  static const planAccentLabel = TextStyle(
    color: RuniacColors.primaryBlue,
    fontSize: 12,
    fontWeight: FontWeight.w800,
  );

  static const bodyStrong = TextStyle(
    color: RuniacColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w800,
  );

  static const calendarTitle = TextStyle(
    color: RuniacColors.textPrimary,
    fontSize: 13,
    fontWeight: FontWeight.w800,
  );

  static const body = TextStyle(
    color: RuniacColors.textSecondary,
    fontSize: 13,
  );

  static const smallBody = TextStyle(
    color: RuniacColors.textSecondary,
    fontSize: 11,
  );

  static const weeklyPlanProgressLabel = TextStyle(
    color: Color(0xBF2F51C8),
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.1,
  );
}
