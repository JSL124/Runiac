/// Number of individual stretch steps that make up the cool-down stretch
/// phase.
///
/// This is a domain-owned contract constant used when requesting the
/// server-computed cool-down XP bonus (`completeCoolDown`). It must stay in
/// sync with `stretchSteps.length` in
/// `lib/features/run/presentation/models/stretch_exercise.dart` — a widget
/// test enforces that the two values match. The data layer reads this
/// constant directly rather than importing the presentation stretch catalog.
const int coolDownStretchStepCount = 14;
