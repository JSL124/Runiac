import 'package:flutter/foundation.dart';

/// Immutable context describing the onboarding step the guide should speak
/// about, plus a read-only view of the answers gathered so far.
///
/// This is the input contract for [OnboardingGuideAgent]. It is intentionally
/// display-oriented and carries no backend-owned values (no XP, level, rank,
/// streak, or leaderboard data).
@immutable
class OnboardingGuideRequest {
  const OnboardingGuideRequest({
    required this.stepId,
    this.stepTitle,
    this.stepHelp,
    this.optionLabels = const <String>[],
    this.answersSoFar = const <String, Object>{},
  });

  /// Stable identifier of the current onboarding step (e.g. `goal`).
  final String stepId;

  /// Human-readable question/title shown on the step, when present.
  final String? stepTitle;

  /// The step's supporting helper copy, when present.
  final String? stepHelp;

  /// Labels of the selectable options on this step, in display order.
  final List<String> optionLabels;

  /// Read-only snapshot of the answers collected so far, keyed by answer key.
  ///
  /// A future remote agent may use this for more personalized hints. The
  /// rule-based agent uses it sparingly and never derives backend-owned values
  /// from it.
  final Map<String, Object> answersSoFar;
}

/// A short, friendly guide message for the current onboarding step.
@immutable
class OnboardingGuideMessage {
  const OnboardingGuideMessage({required this.text});

  /// Beginner-friendly hint copy to render inside the character speech bubble.
  final String text;
}

/// Seam for the onboarding guide "brain".
///
/// The API is [Future]-based on purpose so a future remote implementation fits
/// without changing callers. A planned `OpenAiOnboardingGuideAgent` will call a
/// Cloud Function proxy that holds the OpenAI API key server-side only; the
/// client must never embed an API key or call the OpenAI API directly. Today
/// only [RuleBasedOnboardingGuideAgent] exists and it performs no network I/O.
abstract interface class OnboardingGuideAgent {
  /// Produces a guide message for the step described by [request].
  Future<OnboardingGuideMessage> guide(OnboardingGuideRequest request);
}
