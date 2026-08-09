enum PlanFamily {
  returnToMovement,
  runWalkFoundation,
  firstContinuousRunningStart,
  consistencyBase,
  fiveKBaseBuilder,
  tenKFoundation,
  fiveKPerformanceBuild,
  tenKPerformanceBuild,
}

enum PlanFamilyCategory { starter, developing, performance }

class ResolvedPlanFamily {
  const ResolvedPlanFamily({
    required this.family,
    required this.category,
    required this.reason,
  });

  const ResolvedPlanFamily.blocked()
    : family = null,
      category = null,
      reason =
          'Running plan generation is paused until these answers are reviewed.';

  final PlanFamily? family;
  final PlanFamilyCategory? category;
  final String reason;
}

extension PlanFamilyCopy on PlanFamily {
  String get title {
    return switch (this) {
      PlanFamily.returnToMovement => 'Return to Movement',
      PlanFamily.runWalkFoundation => 'Run-Walk Foundation',
      PlanFamily.firstContinuousRunningStart =>
        'First Continuous Running Start',
      PlanFamily.consistencyBase => 'Consistency Base',
      PlanFamily.fiveKBaseBuilder => '5K Base Builder',
      PlanFamily.tenKFoundation => '10K Foundation',
      PlanFamily.fiveKPerformanceBuild => '5K Performance Build',
      PlanFamily.tenKPerformanceBuild => '10K Performance Build',
    };
  }

  PlanFamilyCategory get category {
    return switch (this) {
      PlanFamily.returnToMovement ||
      PlanFamily.runWalkFoundation ||
      PlanFamily.firstContinuousRunningStart => PlanFamilyCategory.starter,
      PlanFamily.consistencyBase ||
      PlanFamily.fiveKBaseBuilder ||
      PlanFamily.tenKFoundation => PlanFamilyCategory.developing,
      PlanFamily.fiveKPerformanceBuild ||
      PlanFamily.tenKPerformanceBuild => PlanFamilyCategory.performance,
    };
  }

  int get durationWeeks {
    return switch (category) {
      PlanFamilyCategory.starter => 4,
      PlanFamilyCategory.developing => 6,
      PlanFamilyCategory.performance => 8,
    };
  }
}
