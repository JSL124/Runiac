import 'package:runiac_app/core/assets/runiac_assets.dart';

class StretchExercise {
  const StretchExercise({
    required this.name,
    required this.subtitle,
    required this.assetPath,
    required this.seconds,
    required this.perSide,
  });
  final String name;
  final String subtitle;
  final String assetPath;
  final int seconds;
  final bool perSide;
}

enum StretchSide { left, right }

class StretchStep {
  const StretchStep({required this.exercise, required this.exerciseIndex, this.side});
  final StretchExercise exercise;
  final int exerciseIndex; // 0..7, for "Stretch X of 8"
  final StretchSide? side; // null when exercise.perSide == false
  int get seconds => exercise.seconds;
}

const List<StretchExercise> stretchExercises = [
  StretchExercise(
    name: 'Standing Calf Stretch',
    subtitle: 'Calf stretch',
    assetPath: RuniacAssets.stretchingStandingCalf,
    seconds: 25,
    perSide: true,
  ),
  StretchExercise(
    name: 'Standing Quadriceps Stretch',
    subtitle: 'Front thigh stretch',
    assetPath: RuniacAssets.stretchingStandingQuadriceps,
    seconds: 25,
    perSide: true,
  ),
  StretchExercise(
    name: 'Hamstring Stretch',
    subtitle: 'Back thigh stretch',
    assetPath: RuniacAssets.stretchingHamstring,
    seconds: 25,
    perSide: true,
  ),
  StretchExercise(
    name: 'Hip Flexor Lunge Stretch',
    subtitle: 'Hip flexor stretch',
    assetPath: RuniacAssets.stretchingHipFlexorLunge,
    seconds: 25,
    perSide: true,
  ),
  StretchExercise(
    name: 'Figure Four Glute Stretch',
    subtitle: 'Hip and glute stretch',
    assetPath: RuniacAssets.stretchingFigureFourGlute,
    seconds: 25,
    perSide: true,
  ),
  StretchExercise(
    name: 'Adductor Side Lunge Stretch',
    subtitle: 'Inner thigh stretch',
    assetPath: RuniacAssets.stretchingAdductorSideLunge,
    seconds: 25,
    perSide: true,
  ),
  StretchExercise(
    name: 'Kneeling Shin Stretch',
    subtitle: 'Shin stretch',
    assetPath: RuniacAssets.stretchingKneelingShin,
    seconds: 20,
    perSide: false,
  ),
  StretchExercise(
    name: "Child's Pose",
    subtitle: 'Lower back and spine release',
    assetPath: RuniacAssets.stretchingChildsPose,
    seconds: 30,
    perSide: false,
  ),
];

final List<StretchStep> stretchSteps = [
  for (final (i, e) in stretchExercises.indexed)
    if (e.perSide) ...[
      StretchStep(exercise: e, exerciseIndex: i, side: StretchSide.left),
      StretchStep(exercise: e, exerciseIndex: i, side: StretchSide.right),
    ] else
      StretchStep(exercise: e, exerciseIndex: i),
];

final int stretchTotalSeconds =
    stretchSteps.fold(0, (sum, step) => sum + step.seconds); // 350
