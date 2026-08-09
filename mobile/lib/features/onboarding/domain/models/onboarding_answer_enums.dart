/// The answer sets for the onboarding questionnaire.
///
/// Every enum carries an explicit string [value] rather than relying on its
/// Dart name, because these answers are persisted and are read back by the plan
/// generator. Renaming a case is therefore safe; changing its `value` breaks
/// every stored draft and must not be done casually.
enum OnboardingGoal {
  habit('habit'),
  gentle('gentle'),
  first5k('5k'),
  tenK('10k'),
  stamina('stamina');

  const OnboardingGoal(this.value);

  final String value;

  static OnboardingGoal? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingExperience {
  newRunner('new'),
  walk('walk'),
  intervals('intervals'),
  run10('run10'),
  run30('run30');

  const OnboardingExperience(this.value);

  final String value;

  static OnboardingExperience? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum RecentRunningConsistency {
  none('none'),
  underFourWeeks('under4'),
  oneToThreeMonths('1-3m'),
  threeToSixMonths('3-6m'),
  sixMonthsPlus('6plus');

  const RecentRunningConsistency(this.value);

  final String value;

  static RecentRunningConsistency? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum CurrentWeeklyRunFrequency {
  zero('0'),
  oneToTwo('1-2'),
  three('3'),
  four('4'),
  fivePlus('5plus');

  const CurrentWeeklyRunFrequency(this.value);

  final String value;

  static CurrentWeeklyRunFrequency? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum ContinuousRunCapacity {
  walkOnly('walk'),
  runWalk('runwalk'),
  tenMinutes('10min'),
  twentyToThirtyMinutes('20-30min'),
  fortyFivePlusMinutes('45plus'),
  sixtyPlusMinutes('60plus');

  const ContinuousRunCapacity(this.value);

  final String value;

  static ContinuousRunCapacity? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingAvailability {
  two('2'),
  three('3'),
  four('4'),
  unsure('unsure');

  const OnboardingAvailability(this.value);

  final String value;

  static OnboardingAvailability? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingPreferredDay {
  mon('Mon'),
  tue('Tue'),
  wed('Wed'),
  thu('Thu'),
  fri('Fri'),
  sat('Sat'),
  sun('Sun');

  const OnboardingPreferredDay(this.value);

  final String value;

  static OnboardingPreferredDay? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingPreferredTime {
  morning('morning'),
  afternoon('afternoon'),
  evening('evening'),
  night('night'),
  flexible('flexible');

  const OnboardingPreferredTime(this.value);

  final String value;

  static OnboardingPreferredTime? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingSessionLength {
  fifteen('15'),
  twenty('20'),
  thirty('30'),
  fortyFive('45'),
  unsure('unsure');

  const OnboardingSessionLength(this.value);

  final String value;

  static OnboardingSessionLength? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingRunningPlace {
  park('park'),
  road('road'),
  track('track'),
  treadmill('treadmill'),
  mixed('mixed');

  const OnboardingRunningPlace(this.value);

  final String value;

  static OnboardingRunningPlace? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingMotivationStyle {
  reminders('reminders'),
  plan('plan'),
  encourage('encourage'),
  challenge('challenge'),
  expert('expert');

  const OnboardingMotivationStyle(this.value);

  final String value;

  static OnboardingMotivationStyle? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingHealthComfort {
  ready('ready'),
  breakAfterTimeAway('break'),
  injury('injury'),
  heart('heart'),
  asthma('asthma'),
  joint('joint'),
  advised('advised'),
  unsure('unsure');

  const OnboardingHealthComfort(this.value);

  final String value;

  static OnboardingHealthComfort? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingActivitySymptom {
  chest('chest'),
  dizzy('dizzy'),
  breath('breath'),
  heartbeat('heartbeat'),
  legpain('legpain'),
  none('none');

  const OnboardingActivitySymptom(this.value);

  final String value;

  static OnboardingActivitySymptom? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingPlanCautiousness {
  veryGentle('verygentle'),
  balanced('balanced'),
  standard('standard'),
  unsure('unsure');

  const OnboardingPlanCautiousness(this.value);

  final String value;

  static OnboardingPlanCautiousness? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

enum OnboardingPlanStyle {
  conservativeBase('conservative'),
  balanced('balanced'),
  performanceFocused('performance'),
  auto('auto');

  const OnboardingPlanStyle(this.value);

  final String value;

  static OnboardingPlanStyle? fromValue(String? value) =>
      _enumByValue(values, value, (item) => item.value);
}

OnboardingPlanStyle planStyleFromCautiousness(
  OnboardingPlanCautiousness cautiousness,
) {
  return switch (cautiousness) {
    OnboardingPlanCautiousness.veryGentle =>
      OnboardingPlanStyle.conservativeBase,
    OnboardingPlanCautiousness.balanced => OnboardingPlanStyle.balanced,
    OnboardingPlanCautiousness.standard => OnboardingPlanStyle.balanced,
    OnboardingPlanCautiousness.unsure => OnboardingPlanStyle.auto,
  };
}

int requiredPreferredDayCountForAvailability(
  OnboardingAvailability availability,
) {
  return switch (availability) {
    OnboardingAvailability.two => 2,
    OnboardingAvailability.three => 3,
    OnboardingAvailability.four => 4,
    OnboardingAvailability.unsure => 2,
  };
}

T? _enumByValue<T extends Enum>(
  List<T> values,
  String? value,
  String Function(T item) itemValue,
) {
  for (final item in values) {
    if (itemValue(item) == value) {
      return item;
    }
  }
  return null;
}
