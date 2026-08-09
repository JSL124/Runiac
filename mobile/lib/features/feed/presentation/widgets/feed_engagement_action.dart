import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../you/presentation/widgets/you_surface_primitives.dart';

class FeedEngagementAction extends StatelessWidget {
  const FeedEngagementAction({
    required this.label,
    required this.icon,
    required this.value,
    required this.highlighted,
    required this.enabled,
    required this.onPressed,
    required this.actionKey,
    super.key,
  });

  final String label;
  final IconData icon;
  final String value;
  final bool highlighted;
  final bool enabled;
  final VoidCallback onPressed;
  final Key actionKey;

  @override
  Widget build(BuildContext context) {
    final color = _actionColor();

    return Semantics(
      key: actionKey,
      label: label,
      button: enabled,
      enabled: enabled,
      container: true,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 5),
                Text(
                  value,
                  style: YouTextStyles.smallStrong.copyWith(color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _actionColor() {
    if (!enabled) {
      return RuniacColors.disabledButtonForeground;
    }
    if (highlighted) {
      return RuniacColors.accentOrange;
    }
    return RuniacColors.textSecondary;
  }
}
