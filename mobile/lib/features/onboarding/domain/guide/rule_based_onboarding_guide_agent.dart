import 'onboarding_guide_agent.dart';

/// Offline, deterministic [OnboardingGuideAgent] used today.
///
/// It maps each onboarding step id to friendly, beginner-facing hint copy that
/// explains what the question means and how to think about answering it. It
/// performs no network I/O and derives no backend-owned values.
///
/// A future `OpenAiOnboardingGuideAgent` is expected to implement the same
/// [OnboardingGuideAgent] seam by calling a Cloud Function proxy that keeps the
/// OpenAI API key server-side; this rule-based agent is the safe default and
/// the fallback when a remote hint is unavailable.
class RuleBasedOnboardingGuideAgent implements OnboardingGuideAgent {
  const RuleBasedOnboardingGuideAgent();

  @override
  Future<OnboardingGuideMessage> guide(OnboardingGuideRequest request) async {
    final text = _hintForStep(request.stepId) ?? _fallbackHint(request);
    return OnboardingGuideMessage(text: text);
  }

  String? _hintForStep(String stepId) => _hintsByStepId[stepId];

  String _fallbackHint(OnboardingGuideRequest request) {
    final title = request.stepTitle?.trim();
    if (title != null && title.isNotEmpty) {
      return "Take your time. There's no wrong answer here — just pick what "
          'feels closest to you and we can adjust it later.';
    }
    return "No rush at all. Pick whatever feels closest, and you can change "
        'it later.';
  }

  /// Beginner-friendly hint copy for every onboarding step.
  static const Map<String, String> _hintsByStepId = <String, String>{
    'welcome':
        "Hi! I'm your running buddy. These quick questions help Runiac shape "
        'a gentle plan that fits you. Tap Start setup whenever you feel ready.',
    'goal':
        'Think about why you want to run. Just building a habit is a great '
        'goal on its own — you can always aim higher later.',
    'consistency':
        'This is about your recent weeks, not your best-ever stretch. Being '
        'honest here helps Runiac start you at a comfortable place.',
    'frequency':
        'Count a normal week, not a busy or perfect one. Even zero is totally '
        'fine — everyone starts somewhere.',
    'capacity':
        "Pick the longest easy effort you could repeat without struggling. If "
        "you mostly walk right now, choose walking — that's a strong start.",
    'experience':
        "This is just your starting point, not a test. Choose whatever "
        "describes you today and we'll build up gently from there.",
    'availability':
        'Choose days you can realistically keep, even on a busy week. Two or '
        'three days is plenty to build a lasting habit.',
    'days':
        'Pick the days that usually fit your routine. Spacing runs out with '
        'rest days between them helps your body recover.',
    'time':
        'Choose when you naturally have energy. This only helps time your '
        'gentle reminders — you can still run whenever suits you.',
    'length':
        'Shorter is smarter at the start. A short session you finish beats a '
        'long one you dread, so feel free to keep it easy.',
    'place':
        'Pick where you usually run so distances feel familiar. Mixed is fine '
        'if it changes day to day.',
    'motivation':
        'Think about what actually keeps you going — a nudge, a clear plan, or '
        'kind encouragement. Runiac leans into whatever you choose.',
    'health':
        "Share only what you're comfortable with. This helps Runiac start you "
        "gently. If something worries you, it's always okay to check with a "
        'healthcare professional first.',
    'symptoms':
        'These are just things to be aware of during activity. If you ever '
        "feel them, it's a good idea to slow down and speak with a healthcare "
        'professional. Choose None of these if none apply.',
    'style':
        'This sets how your plan should feel. Keep it gentle if you want more '
        "easy effort, or let Runiac choose the calmest fit from your answers.",
    'preview':
        "Here's the starting plan built from your answers. Nothing is locked "
        'in — you can edit your answers or adjust it anytime.',
  };
}
