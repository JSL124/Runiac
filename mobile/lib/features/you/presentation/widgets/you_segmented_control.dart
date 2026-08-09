import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import 'you_surface_primitives.dart';

class YouSegmentedControl extends StatelessWidget {
  const YouSegmentedControl({
    required this.labels,
    required this.selected,
    this.onTap,
    this.compact = false,
    super.key,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int>? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: youPillDecoration(RuniacColors.white),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                enabled: onTap != null,
                selected: i == selected,
                label: '${labels[i]} tab',
                onTap: onTap == null ? null : () => onTap!(i),
                excludeSemantics: true,
                child: GestureDetector(
                  onTap: onTap == null ? null : () => onTap!(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected ? RuniacColors.primaryBlue : null,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: i == selected
                            ? RuniacColors.white
                            : RuniacColors.textPrimary,
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
