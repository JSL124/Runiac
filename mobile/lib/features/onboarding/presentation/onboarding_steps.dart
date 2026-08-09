import 'onboarding_step_config.dart';

const onboardingSteps = [...onboardingSetupSteps, ..._onboardingSafetySteps];

const _onboardingSafetySteps = [
  OnboardingStep(
    id: 'health',
    kind: OnboardingStepKind.single,
    answerKey: 'health',
    title: 'Anything we should keep in mind?',
    help:
        "This helps us start you gently. Share only what you're comfortable with.",
    disclaimer: true,
    options: [
      OnboardingOption('ready', "No, I'm ready to start"),
      OnboardingOption('break', 'Returning after a long break'),
      OnboardingOption('injury', 'Currently managing an injury or pain'),
      OnboardingOption('heart', 'Heart or blood pressure condition'),
      OnboardingOption('asthma', 'Asthma or breathing difficulty'),
      OnboardingOption('joint', 'Joint, knee, ankle, or back concern'),
      OnboardingOption(
        'advised',
        'A professional advised me to limit exercise',
      ),
      OnboardingOption('unsure', 'Not sure'),
    ],
  ),
  OnboardingStep(
    id: 'symptoms',
    kind: OnboardingStepKind.multi,
    answerKey: 'symptoms',
    title: 'During activity, do you ever notice any of these?',
    banner: OnboardingBannerKind.symptoms,
    disclaimer: true,
    noneValue: 'none',
    options: [
      OnboardingOption('chest', 'Chest pain or discomfort'),
      OnboardingOption('dizzy', 'Dizziness or fainting'),
      OnboardingOption('breath', 'Unusual shortness of breath'),
      OnboardingOption('heartbeat', 'Irregular or very fast heartbeat'),
      OnboardingOption('legpain', 'Severe leg pain'),
      OnboardingOption('none', 'None of these'),
    ],
  ),
  OnboardingStep(
    id: 'style',
    kind: OnboardingStepKind.single,
    answerKey: 'style',
    title: 'How would you like your training plan to feel?',
    help:
        'Preference shapes the plan, but your recent running decides the level.',
    options: [
      OnboardingOption(
        'conservative',
        'Keep it gentle',
        sub: 'More easy effort and slower progression.',
      ),
      OnboardingOption(
        'balanced',
        'Balanced progression',
        sub: 'A comfortable mix of easy running and gradual build.',
      ),
      OnboardingOption(
        'performance',
        'Build steadily',
        sub: 'A little more structure, only if your answers support it.',
      ),
      OnboardingOption(
        'auto',
        'Let Runiac decide',
        sub: "We'll choose the safest fit from your answers.",
      ),
    ],
  ),
  OnboardingStep(
    id: 'preview',
    kind: OnboardingStepKind.preview,
    title: 'Your plan preview is ready',
  ),
];

const onboardingPreviewLabels = {
  'goal': {
    'habit': 'Build a running habit',
    'gentle': 'Start running gently',
    '5k': 'Complete my first 5K',
    '10k': 'Work toward a 10K',
    'stamina': 'Improve my stamina',
  },
  'experience': {
    'new': 'New to running',
    'walk': 'Can walk 20-30 min',
    'intervals': 'Run / walk intervals',
    'run10': 'Can run about 10 min',
    'run30': 'Can run 20-30 min',
  },
  'consistency': {
    'none': 'Not running yet',
    'under4': 'Under 4 weeks',
    '1-3m': '1-3 months',
    '3-6m': '3-6 months',
    '6plus': '6+ months',
  },
  'frequency': {
    '0': '0 runs / week',
    '1-2': '1-2 runs / week',
    '3': '3 runs / week',
    '4': '4 runs / week',
    '5plus': '5+ runs / week',
  },
  'capacity': {
    'walk': 'Mostly walking',
    'runwalk': 'Run-walk intervals',
    '10min': 'About 10 min',
    '20-30min': '20-30 min',
    '45plus': '45+ min',
    '60plus': '60+ min',
  },
  'availability': {
    '2': '2 runs / week',
    '3': '3 runs / week',
    '4': '4 runs / week',
    'unsure': '3 runs / week',
  },
  'length': {
    '15': '15 min',
    '20': '20 min',
    '30': '30 min',
    '45': '45 min',
    'unsure': '15-20 min',
  },
  'cautious': {
    'verygentle': 'Very gentle',
    'balanced': 'Balanced beginner',
    'standard': 'Standard beginner',
    'unsure': 'Balanced beginner',
  },
  'style': {
    'conservative': 'Keep it gentle',
    'balanced': 'Balanced progression',
    'performance': 'Build steadily',
    'auto': 'Let Runiac decide',
  },
};
