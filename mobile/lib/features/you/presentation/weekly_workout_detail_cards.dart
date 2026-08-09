part of 'weekly_workout_detail_screen.dart';

class _WorkoutBreakdownCard extends StatelessWidget {
  const _WorkoutBreakdownCard(this.steps);

  final List<WorkoutStepDisplay> steps;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Session breakdown', style: _sectionTitleStyle),
          const SizedBox(height: 12),
          for (var index = 0; index < steps.length; index++) ...[
            _WorkoutStepRow(steps[index]),
            if (index < steps.length - 1)
              const Divider(height: 20, color: RuniacColors.border),
          ],
        ],
      ),
    );
  }
}

class _WorkoutStepRow extends StatelessWidget {
  const _WorkoutStepRow(this.step);

  final WorkoutStepDisplay step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: _softIconDecoration,
          child: Icon(step.icon, color: RuniacColors.primaryBlue, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(step.title, style: _bodyStrongStyle),
              const SizedBox(height: 3),
              Text(step.copy, style: _bodyStyle),
            ],
          ),
        ),
      ],
    );
  }
}

class _EffortGuideCard extends StatelessWidget {
  const _EffortGuideCard(this.copy);

  final String copy;

  @override
  Widget build(BuildContext context) {
    return DashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Effort guide', style: _sectionTitleStyle),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var index = 0; index < 5; index++) ...[
                Expanded(
                  child: Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: index < 2
                          ? RuniacColors.primaryBlue
                          : const Color(0xFFE8EEF8),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                if (index < 4) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(copy, style: _bodyStyle),
        ],
      ),
    );
  }
}

// The static Coach note card used to live here. Its `snapshot.coachNotes` copy
// is now prompt context for the AI briefing behind the header's sparkle button
// instead of on-screen text, so the notes still steer what the runner is told —
// they are just explained rather than recited.

/// Header action that opens the AI briefing for this planned workout.
///
/// Mirrors the Activity Summary sparkle button: paywall-gate first, then a
/// blocking overlay whose character runs in while the request is already in
/// flight.
class _WorkoutBriefingActionButton extends StatelessWidget {
  const _WorkoutBriefingActionButton({required this.snapshot, this.agent});

  final WeeklyWorkoutDetailSnapshot snapshot;
  final WorkoutBriefingAgent? agent;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const ValueKey('workout_briefing_icon_action'),
      tooltip: "Explain today's workout",
      onPressed: () => _open(context),
      style: IconButton.styleFrom(
        foregroundColor: RuniacColors.primaryBlue,
        minimumSize: const Size(40, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Image.asset(
        RuniacAssets.activityFeedbackSparkle,
        width: 22,
        height: 22,
        fit: BoxFit.contain,
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    if (interceptWithPaywallIfGated(context, 'workoutBriefing')) {
      return;
    }
    final character =
        SelectedRunnerCharacterScope.maybeOf(context)?.selectedOrDefault ??
        RunnerCharacter.blue;
    final resolvedAgent = agent ?? _defaultAgent();
    final request = _requestFor(snapshot);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return CharacterGuidanceOverlay(
          character: character,
          keyPrefix: 'workout_briefing',
          loadingCopy: 'Reading your plan...',
          closeTooltip: 'Close workout briefing',
          previousTooltip: 'Previous briefing step',
          nextTooltip: 'Next briefing step',
          loadSteps: () async {
            final bundle = await resolvedAgent.explainPlannedWorkout(request);
            final steps = <CharacterGuidanceStep>[
              for (final step in bundle.sections.steps)
                CharacterGuidanceStep(title: step.title, body: step.body),
            ];
            // Same reason as the activity-feedback overlay: a quota refusal is
            // otherwise indistinguishable from a provider outage, and states no
            // reset day. See `agentQuotaResetNotice`.
            return guidanceStepsWithLeadingNotice(
              steps,
              bundle.source == WorkoutBriefingSource.quota
                  ? agentQuotaResetNotice(
                      retryAfterDate: bundle.retryAfterDate,
                      subject: 'your workout briefing',
                    )
                  : null,
            );
          },
          onClose: () => Navigator.of(dialogContext, rootNavigator: true).pop(),
        );
      },
    );
  }

  WorkoutBriefingAgent _defaultAgent() {
    return CachingWorkoutBriefingAgent(
      delegate: CloudFunctionWorkoutBriefingAgent(),
    );
  }

  /// Only display copy the runner is already looking at. `planId` reaches the
  /// request as cache-key material and is dropped by the payload builder.
  WorkoutBriefingRequest _requestFor(WeeklyWorkoutDetailSnapshot snapshot) {
    final briefingContext = snapshot.briefingContext;
    return WorkoutBriefingRequest(
      dayLabel: snapshot.dayLabel,
      planTitle: snapshot.planTitle,
      effortGuide: snapshot.effortGuide,
      weekNumber: briefingContext?.weekNumber,
      weekFocus: briefingContext?.weekFocus,
      metrics: [
        for (final metric in snapshot.metrics)
          WorkoutBriefingMetric(label: metric.label, value: metric.value),
      ],
      steps: [
        for (final step in snapshot.breakdown)
          WorkoutBriefingStep(title: step.title, detail: step.copy),
      ],
      coachNotes: snapshot.coachNotes,
      cacheIdentity: briefingContext == null
          ? null
          : '${briefingContext.planId}'
                '|w${briefingContext.weekNumber}'
                '|${snapshot.dayLabel}',
    );
  }
}

class _StartRunAction extends StatelessWidget {
  const _StartRunAction(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RuniacTappableSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: RuniacColors.accentOrange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: _startActionStyle),
    );
  }
}

Future<void> _showEditScheduleSheet(
  BuildContext context,
  WeeklyWorkoutDetailSnapshot snapshot,
  ValueChanged<WorkoutScheduleEditSelection>? onScheduleChanged,
) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: RuniacColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) => _EditScheduleSheet(
      snapshot: snapshot,
      onScheduleChanged: onScheduleChanged,
    ),
  );
  if (saved != true || !context.mounted) {
    return;
  }
  await showRuniacSuccessCheckOverlay(context, message: 'Schedule updated.');
}
