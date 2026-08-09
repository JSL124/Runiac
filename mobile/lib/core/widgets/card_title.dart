import 'package:flutter/material.dart';

import '../theme/runiac_colors.dart';

class CardTitle extends StatelessWidget {
  const CardTitle({
    required this.icon,
    required this.title,
    this.accent = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: accent ? const Color(0x1AFC6818) : const Color(0x1A2F50C7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: accent
                ? RuniacColors.accentOrange
                : RuniacColors.primaryBlue,
            size: 18,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: RuniacColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}
