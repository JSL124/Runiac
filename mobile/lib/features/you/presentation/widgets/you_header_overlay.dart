import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import 'you_surface_primitives.dart';

class YouHeaderOverlay extends StatelessWidget {
  const YouHeaderOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RuniacColors.background,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('You', style: YouTextStyles.headerTitle),
              SizedBox(height: 8),
              YouHeaderAccentStrip(),
            ],
          ),
        ),
      ),
    );
  }
}
