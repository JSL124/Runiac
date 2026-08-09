import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/assets/runiac_assets.dart';
import '../../../core/characters/runner_character.dart';
import '../../../core/formatting/agent_quota_notice.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/character_guidance_overlay.dart';
import '../../../core/widgets/dashboard_card.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_bottom_sheet_handle.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../../../core/widgets/runiac_success_check_overlay.dart';
import '../../paywall/presentation/premium_gate.dart';
import '../../run/presentation/active_run_session_coordinator.dart';
import '../../run/presentation/run_launch_screen.dart';
import '../data/cloud_function_workout_briefing_agent.dart';
import '../domain/models/workout_briefing_agent.dart';
import 'data/weekly_workout_demo_snapshots.dart';

part 'weekly_workout_detail_action_icon.dart';
part 'weekly_workout_detail_overview.dart';
part 'weekly_workout_detail_cards.dart';
part 'weekly_workout_schedule_sheet.dart';
part 'weekly_workout_schedule_chrome.dart';
part 'weekly_workout_schedule_selection.dart';
part 'weekly_workout_time_picker.dart';
part 'weekly_workout_time_picker_widgets.dart';

class WeeklyWorkoutDetailScreen extends StatelessWidget {
  const WeeklyWorkoutDetailScreen({
    required this.onBack,
    this.snapshot = weeklyWorkoutDetailSnapshot,
    this.showEditScheduleAction = true,
    this.enableForegroundGps = true,
    this.onStartRun,
    this.onScheduleChanged,
    this.activeRunSessionCoordinator,
    this.workoutBriefingAgent,
    super.key,
  });

  final VoidCallback onBack;
  final WeeklyWorkoutDetailSnapshot snapshot;
  final bool showEditScheduleAction;
  final bool enableForegroundGps;
  final VoidCallback? onStartRun;
  final ValueChanged<WorkoutScheduleEditSelection>? onScheduleChanged;
  final ActiveRunSessionCoordinator? activeRunSessionCoordinator;

  /// Test seam. Left null in the app so the real agent is built at tap time,
  /// which keeps this screen out of the app-wide scope wiring.
  final WorkoutBriefingAgent? workoutBriefingAgent;

  Future<void> _openRunLaunch(BuildContext context) async {
    final initialPreviewCurrentPosition =
        await prewarmRunLaunchPreviewCurrentPosition(
          enableForegroundGps: enableForegroundGps,
        );
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RunLaunchScreen(
          enableForegroundGps: enableForegroundGps,
          initialPreviewCurrentPosition: initialPreviewCurrentPosition,
          activeRunSessionCoordinator: activeRunSessionCoordinator,
          plannedWorkout: snapshot.plannedRunContext,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final startActionLabel = snapshot.startActionLabel;
    return Material(
      color: RuniacColors.background,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: RuniacBackHeader(
                title: snapshot.title,
                titleKey: const ValueKey('workout_detail_header_title'),
                titleStyle: _headerTitleStyle,
                titleMaxLines: 2,
                titleOverflow: TextOverflow.visible,
                height: 64,
                tooltip: 'Back to Plans',
                onBack: onBack,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _WorkoutBriefingActionButton(
                      snapshot: snapshot,
                      agent: workoutBriefingAgent,
                    ),
                    if (showEditScheduleAction && snapshot.canEditSchedule)
                      IconButton(
                        key: const ValueKey('edit_schedule_icon_action'),
                        tooltip: 'Edit schedule',
                        onPressed: () => _showEditScheduleSheet(
                          context,
                          snapshot,
                          onScheduleChanged,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 44,
                          height: 44,
                        ),
                        icon: const _EditScheduleActionIcon(),
                      ),
                  ],
                ),
                trailingWidth:
                    showEditScheduleAction && snapshot.canEditSchedule
                    ? 88
                    : 48,
              ),
            ),
            Expanded(
              child: _NoOverscroll(
                key: const ValueKey('workout_detail_no_overscroll'),
                child: ListView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                  children: [
                    _WorkoutPlanIdentity(snapshot),
                    const SizedBox(height: 10),
                    _MetricSummaryCard(snapshot.metrics),
                    const SizedBox(height: 12),
                    _WorkoutBreakdownCard(snapshot.breakdown),
                    const SizedBox(height: 12),
                    _EffortGuideCard(snapshot.effortGuide),
                    if (startActionLabel != null) ...[
                      const SizedBox(height: 16),
                      _StartRunAction(
                        startActionLabel,
                        onTap: onStartRun ?? () => _openRunLaunch(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
