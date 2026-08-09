import 'package:flutter/material.dart';

import '../../../you/presentation/widgets/you_surface_primitives.dart';

class FeedHeader extends StatelessWidget {
  const FeedHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          header: true,
          child: const Text('Feed', style: YouTextStyles.headerTitle),
        ),
        const SizedBox(height: 8),
        const YouHeaderAccentStrip(),
      ],
    );
  }
}
