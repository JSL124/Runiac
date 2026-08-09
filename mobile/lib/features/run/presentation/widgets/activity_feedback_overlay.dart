import 'package:flutter/material.dart';

import '../../../../core/characters/runner_character.dart';
import '../../../../core/formatting/agent_quota_notice.dart';
import '../../../../core/widgets/character_guidance_overlay.dart';
import '../../domain/models/activity_feedback_agent.dart';

/// Kept as the Activity Summary entry point so the run flow's constructor,
/// widget keys, and rendered behaviour are unchanged. The motion, reduced-motion
/// handling, close semantics, and bubble layout now live in the shared
/// [CharacterGuidanceOverlay], which also owns the run-in duration.
class ActivityFeedbackOverlay extends StatelessWidget {
  const ActivityFeedbackOverlay({
    required this.character,
    required this.loadFeedback,
    required this.onClose,
    super.key,
  });

  final RunnerCharacter character;
  final Future<ActivityFeedbackBundle> Function() loadFeedback;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return CharacterGuidanceOverlay(
      character: character,
      onClose: onClose,
      loadingCopy: 'Analysing your run...',
      closeTooltip: 'Close activity feedback',
      previousTooltip: 'Previous feedback step',
      nextTooltip: 'Next feedback step',
      loadSteps: () async {
        final bundle = await loadFeedback();
        final steps = <CharacterGuidanceStep>[
          for (final step in bundle.sections.steps)
            CharacterGuidanceStep(title: step.title, body: step.body),
        ];
        // A quota refusal serves the same generic sections as any other
        // fallback, so without this the runner cannot tell "the model was
        // unavailable" from "you have used today's generations" — nor when
        // they may try again. The reset day is the server's, never derived here.
        return guidanceStepsWithLeadingNotice(
          steps,
          bundle.source == ActivityFeedbackSource.quota
              ? agentQuotaResetNotice(
                  retryAfterDate: bundle.retryAfterDate,
                  subject: 'personalised feedback',
                )
              : null,
        );
      },
    );
  }
}
