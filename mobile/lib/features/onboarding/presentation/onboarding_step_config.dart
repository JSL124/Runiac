/// The 16-step onboarding questionnaire, described as data.
///
/// The steps are a list of [OnboardingStep] values rather than 16 hand-built
/// screens: one screen widget renders any step from its [OnboardingStepKind],
/// so adding or reordering a question is an edit to this file alone.
///
/// [OnboardingBannerKind] marks the two steps that need a warning rather than
/// just options — location permission, and the health/symptoms answers that
/// feed the safety gate.
enum OnboardingStepKind { welcome, single, multi, preview }

enum OnboardingBannerKind { location, symptoms }

class OnboardingOption {
  const OnboardingOption(this.value, this.label, {this.sub});

  final String value;
  final String label;
  final String? sub;
}

class OnboardingStep {
  const OnboardingStep({
    required this.id,
    required this.kind,
    this.answerKey,
    this.title,
    this.help,
    this.options = const [],
    this.daysGrid = false,
    this.banner,
    this.disclaimer = false,
    this.noneValue,
  });

  final String id;
  final OnboardingStepKind kind;
  final String? answerKey;
  final String? title;
  final String? help;
  final List<OnboardingOption> options;
  final bool daysGrid;
  final OnboardingBannerKind? banner;
  final bool disclaimer;
  final String? noneValue;
}

const onboardingDayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

const onboardingSetupSteps = [
  OnboardingStep(id: 'welcome', kind: OnboardingStepKind.welcome),
  OnboardingStep(
    id: 'goal',
    kind: OnboardingStepKind.single,
    answerKey: 'goal',
    title: 'What would you like to work toward?',
    help: 'Pick the one that fits best. You can change it later.',
    options: [
      OnboardingOption(
        'habit',
        'Build a running habit',
        sub: 'Run a little, often. No distance pressure.',
      ),
      OnboardingOption(
        'gentle',
        'Start running gently',
        sub: 'Ease in with walk-and-run sessions.',
      ),
      OnboardingOption(
        '5k',
        'Complete my first 5K',
        sub: 'A steady, beginner-friendly build-up.',
      ),
      OnboardingOption(
        '10k',
        'Work toward a 10K',
        sub: 'A longer-term goal, taken slowly.',
      ),
      OnboardingOption(
        'stamina',
        'Improve my stamina',
        sub: 'Feel stronger and less out of breath.',
      ),
    ],
  ),
  OnboardingStep(
    id: 'consistency',
    kind: OnboardingStepKind.single,
    answerKey: 'consistency',
    title: 'How consistently have you been running lately?',
    help: 'This helps Runiac choose a safe starting level from your history.',
    options: [
      OnboardingOption('none', 'I am not running yet'),
      OnboardingOption('under4', 'Less than 4 weeks'),
      OnboardingOption('1-3m', '1 to 3 months'),
      OnboardingOption('3-6m', '3 to 6 months'),
      OnboardingOption('6plus', '6 months or more'),
    ],
  ),
  OnboardingStep(
    id: 'frequency',
    kind: OnboardingStepKind.single,
    answerKey: 'frequency',
    title: 'How often are you running right now?',
    help: 'Use your recent normal week, not your best week.',
    options: [
      OnboardingOption('0', '0 runs per week'),
      OnboardingOption('1-2', '1-2 runs per week'),
      OnboardingOption('3', '3 runs per week'),
      OnboardingOption('4', '4 runs per week'),
      OnboardingOption('5plus', '5+ runs per week'),
    ],
  ),
  OnboardingStep(
    id: 'capacity',
    kind: OnboardingStepKind.single,
    answerKey: 'capacity',
    title: 'What is your longest comfortable recent run?',
    help: 'Choose the closest easy effort you can repeat.',
    options: [
      OnboardingOption('walk', 'Mostly walking right now'),
      OnboardingOption('runwalk', 'Run-walk intervals'),
      OnboardingOption('10min', 'About 10 minutes'),
      OnboardingOption('20-30min', '20-30 minutes'),
      OnboardingOption('45plus', '45 minutes or more'),
      OnboardingOption('60plus', '60 minutes or more'),
    ],
  ),
  OnboardingStep(
    id: 'experience',
    kind: OnboardingStepKind.single,
    answerKey: 'experience',
    title: 'Where are you starting from?',
    help: 'This is just your starting point. There are no wrong answers.',
    options: [
      OnboardingOption('new', 'Completely new to running'),
      OnboardingOption('walk', 'I can walk 20-30 minutes'),
      OnboardingOption('intervals', 'I do run / walk intervals'),
      OnboardingOption('run10', 'I can run about 10 minutes'),
      OnboardingOption('run30', 'I can run 20-30 minutes'),
    ],
  ),
  OnboardingStep(
    id: 'availability',
    kind: OnboardingStepKind.single,
    answerKey: 'availability',
    title: 'How many days a week can you run?',
    help: 'Two or three is plenty to build a habit.',
    options: [
      OnboardingOption('2', '2 days per week'),
      OnboardingOption(
        '3',
        '3 days per week',
        sub: 'A comfortable, sustainable rhythm.',
      ),
      OnboardingOption('4', '4 days per week'),
      OnboardingOption(
        'unsure',
        'Not sure yet',
        sub: "We'll suggest a gentle default.",
      ),
    ],
  ),
  OnboardingStep(
    id: 'days',
    kind: OnboardingStepKind.multi,
    answerKey: 'days',
    title: 'Which days feel best?',
    help: 'Choose any that work for you. You can adjust this later.',
    daysGrid: true,
  ),
  OnboardingStep(
    id: 'time',
    kind: OnboardingStepKind.single,
    answerKey: 'time',
    title: 'When do you usually prefer to run?',
    help: 'We use this to time your gentle reminders.',
    options: [
      OnboardingOption('morning', 'Morning'),
      OnboardingOption('afternoon', 'Afternoon'),
      OnboardingOption('evening', 'Evening'),
      OnboardingOption('night', 'Night'),
      OnboardingOption('flexible', 'Flexible', sub: 'Any time of day works.'),
    ],
  ),
  OnboardingStep(
    id: 'length',
    kind: OnboardingStepKind.single,
    answerKey: 'length',
    title: 'How long should each beginner session be?',
    help: 'Shorter sessions are a great way to start.',
    options: [
      OnboardingOption('15', '15 minutes'),
      OnboardingOption('20', '20 minutes', sub: 'A friendly starting length.'),
      OnboardingOption('30', '30 minutes'),
      OnboardingOption('45', '45 minutes'),
      OnboardingOption(
        'unsure',
        'Not sure',
        sub: "We'll keep it short to begin.",
      ),
    ],
  ),
  OnboardingStep(
    id: 'place',
    kind: OnboardingStepKind.single,
    answerKey: 'place',
    title: 'Where do you usually run?',
    banner: OnboardingBannerKind.location,
    options: [
      OnboardingOption('park', 'Outdoor park'),
      OnboardingOption('road', 'Road / neighbourhood'),
      OnboardingOption('track', 'Track'),
      OnboardingOption('treadmill', 'Treadmill'),
      OnboardingOption('mixed', 'Mixed'),
    ],
  ),
  OnboardingStep(
    id: 'motivation',
    kind: OnboardingStepKind.single,
    answerKey: 'motivation',
    title: 'What kind of support keeps you going?',
    help: 'We tune the feel of Runiac around this.',
    options: [
      OnboardingOption(
        'reminders',
        'Gentle reminders',
        sub: 'A soft nudge when a run is due.',
      ),
      OnboardingOption(
        'plan',
        'Clear weekly plan',
        sub: 'Always know what today is for.',
      ),
      OnboardingOption(
        'encourage',
        'Progress encouragement',
        sub: 'Kind notes as you keep showing up.',
      ),
      OnboardingOption(
        'challenge',
        'Friendly challenge',
        sub: 'Light, optional goals. Never pressure.',
      ),
      OnboardingOption(
        'expert',
        'Expert guidance',
        sub: 'Beginner tips from running coaches.',
      ),
    ],
  ),
];
