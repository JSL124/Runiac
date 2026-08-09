import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';

class DashboardCard extends StatelessWidget {
  const DashboardCard({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: RuniacColors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: RuniacColors.cardBorder),
      ),
      child: Padding(padding: const EdgeInsets.all(14), child: child),
    );
  }
}
