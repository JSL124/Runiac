import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_theme.dart';
import '../plan_completion_ceremony.dart';

const planCompletionQaSurfaceName = 'plan_completion';

const _qaSurface = String.fromEnvironment('RUNIAC_QA_SURFACE');

Widget? buildPlanCompletionQaAppFromEnvironment() {
  return buildPlanCompletionQaApp(
    releaseMode: kReleaseMode,
    surface: _qaSurface,
  );
}

@visibleForTesting
Widget? buildPlanCompletionQaApp({
  required bool releaseMode,
  required String surface,
}) {
  if (releaseMode || surface != planCompletionQaSurfaceName) {
    return null;
  }

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Runiac Plan Completion QA',
    theme: buildRuniacTheme(),
    home: const _PlanCompletionQaHost(),
  );
}

/// Stands in for the Home tab so the ceremony can be exercised without
/// Firebase auth or a plan-progress read model. It replays the overlay on
/// first frame and on demand, since the ceremony itself is a dialog rather
/// than a screen.
class _PlanCompletionQaHost extends StatefulWidget {
  const _PlanCompletionQaHost();

  @override
  State<_PlanCompletionQaHost> createState() => _PlanCompletionQaHostState();
}

class _PlanCompletionQaHostState extends State<_PlanCompletionQaHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showPlanCompletionCeremony(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => showPlanCompletionCeremony(context),
          child: const Text('Replay plan completion ceremony'),
        ),
      ),
    );
  }
}
