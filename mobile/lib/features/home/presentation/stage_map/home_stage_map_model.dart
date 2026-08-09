import '../../../plan/domain/models/beginner_adaptive_plan_snapshot.dart';
import '../../../plan/presentation/current_session_generated_plan.dart'
    show isGeneratedPlanSession;
import 'home_stage_background_sequence.dart';

/// Number of day slots rendered per week on the stage map.
const int kHomeStageDaysPerWeek = 7;

enum HomeStageStoneKind { run, rest }

/// Display-only progress state for a stage stone.
///
/// `completed`/`current` for run stones are derived strictly from
/// backend-owned completed scheduled-workout ids; no XP/streak/level value is
/// computed here. Rest-stone states are purely cosmetic dimming based on
/// position and carry no trusted meaning.
enum HomeStageStoneState { completed, current, missed, future }

class HomeStageStone {
  const HomeStageStone({
    required this.weekNumber,
    required this.dayIndex,
    required this.kind,
    required this.state,
    this.scheduledWorkoutId,
    this.workoutTitle,
    this.dayLabel,
  });

  final int weekNumber;
  final int dayIndex;
  final HomeStageStoneKind kind;
  final HomeStageStoneState state;
  final String? scheduledWorkoutId;
  final String? workoutTitle;

  /// Display-only English weekday caption for this stone (e.g. `'Mon'`).
  ///
  /// For plans whose workouts carry real weekday labels, every slot in the
  /// week (run and rest) gets its weekday. For synthetic/positional plans
  /// (e.g. `'Day 1'` labels), only run stones carry a label, copied verbatim
  /// from the workout's `dayLabel`; rest stones are left null. This is purely
  /// cosmetic layout metadata, not a backend-owned schedule value.
  final String? dayLabel;

  bool get isRun => kind == HomeStageStoneKind.run;
  bool get isCurrent => state == HomeStageStoneState.current;
  bool get isCompleted => state == HomeStageStoneState.completed;
  bool get isMissed => state == HomeStageStoneState.missed;
}

class HomeStageWeekSection {
  const HomeStageWeekSection({
    required this.weekNumber,
    required this.backgroundAsset,
    required this.stones,
  });

  final int weekNumber;
  final String backgroundAsset;

  /// Always [kHomeStageDaysPerWeek] stones, ordered day 1 (bottom) to day 7.
  final List<HomeStageStone> stones;
}

class HomeStageMapModel {
  const HomeStageMapModel({
    required this.sections,
    required this.currentWeekIndex,
    required this.todayDayIndex,
    required this.characterDayIndex,
    required this.currentStageId,
  });

  /// Ordered bottom-up: index 0 is plan week 1 (rendered at the bottom).
  final List<HomeStageWeekSection> sections;

  /// Section index of the active week, or null when there are no stages.
  final int? currentWeekIndex;

  /// Day index (within the active week) of the next uncompleted eligible run
  /// stone that should pulse as "today", or null when the week has none.
  final int? todayDayIndex;

  /// Day index (within the active week) where the guide character stands.
  final int? characterDayIndex;

  /// Stable identifier of the character's stage (`"weekIndex:dayIndex"`), used
  /// to detect forward progress between sessions. Null when there are no
  /// stages.
  final String? currentStageId;

  bool get hasStages => sections.isNotEmpty;

  static String stageId(int weekIndex, int dayIndex) => '$weekIndex:$dayIndex';
}

/// Rebuilds the scheduled-workout id used by the generated-plan display layer.
///
/// This mirrors the id scheme used when completed workouts are recorded, so a
/// run stone can be matched against backend-owned completed ids.
String homeStageScheduledWorkoutId({
  required int weekNumber,
  required String dayLabel,
  required String title,
}) {
  final titleSlug = title
      .toLowerCase()
      .replaceAll(RegExp('[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-+$'), '');
  final suffix = titleSlug.isEmpty ? 'workout' : titleSlug;
  return 'week-$weekNumber-${dayLabel.toLowerCase()}-$suffix';
}

/// Canonical 3-letter English weekday labels, Monday-first, matching the
/// labels onboarding writes onto generated-plan workouts
/// (`onboardingDayNames` in the onboarding step config).
const List<String> kHomeStageWeekdayLabels = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// Matches [label] against [kHomeStageWeekdayLabels] case-insensitively,
/// returning the Mon=0..Sun=6 slot index, or null when [label] is not one of
/// the 7 weekday labels (e.g. a synthetic `'Day 1'` fallback label).
int? _weekdaySlotIndexFor(String label) {
  final normalized = label.trim().toLowerCase();
  for (var i = 0; i < kHomeStageWeekdayLabels.length; i++) {
    if (kHomeStageWeekdayLabels[i].toLowerCase() == normalized) {
      return i;
    }
  }
  return null;
}

/// True when every workout in [plan] carries a real weekday `dayLabel`
/// (Mon..Sun). When false, at least one week uses synthetic labels (e.g.
/// `'Day 1'`), and the whole plan must fall back to positional day-slot
/// layout instead of scattering stones by weekday.
bool _planUsesWeekdayLabels(BeginnerAdaptivePlanSnapshot plan) {
  for (final week in plan.weeks) {
    for (final workout in week.workouts) {
      if (_weekdaySlotIndexFor(workout.dayLabel) == null) {
        return false;
      }
    }
  }
  return true;
}

class _RawStone {
  const _RawStone({
    required this.kind,
    required this.completed,
    required this.dayLabel,
    required this.scheduledWorkoutId,
    required this.workoutTitle,
  });

  final HomeStageStoneKind kind;
  final bool completed;
  final String? dayLabel;
  final String? scheduledWorkoutId;
  final String? workoutTitle;
}

/// Pure builder that turns a plan + backend completion set into a renderable
/// stage map. No trusted value is computed; run completion comes only from
/// [completedScheduledWorkoutIds].
HomeStageMapModel buildHomeStageMapModel({
  required BeginnerAdaptivePlanSnapshot plan,
  required Set<String> completedScheduledWorkoutIds,
  required int activeWeekNumber,
  int? currentWeekdayIndex,
  required List<String> backgroundSequence,
}) {
  if (plan.weeks.isEmpty) {
    return const HomeStageMapModel(
      sections: <HomeStageWeekSection>[],
      currentWeekIndex: null,
      todayDayIndex: null,
      characterDayIndex: null,
      currentStageId: null,
    );
  }

  // Whole-plan decision: only lay stones out by real weekday when every
  // workout in every week carries a Mon..Sun label. Mixed/synthetic-label
  // plans keep the positional layout so they never scatter randomly.
  final useWeekdaySlots = _planUsesWeekdayLabels(plan);

  final rawByWeek = <List<_RawStone>>[];
  for (var w = 0; w < plan.weeks.length; w++) {
    final week = plan.weeks[w];
    rawByWeek.add(
      useWeekdaySlots
          ? _weekdaySlottedRawStones(
              week: week,
              completedScheduledWorkoutIds: completedScheduledWorkoutIds,
            )
          : _positionalRawStones(
              week: week,
              completedScheduledWorkoutIds: completedScheduledWorkoutIds,
            ),
    );
  }

  // Resolve the active week section index.
  var currentWeekIndex = plan.weeks.indexWhere(
    (week) => week.weekNumber == activeWeekNumber,
  );
  if (currentWeekIndex < 0) {
    currentWeekIndex = 0;
  }

  final activeRaw = rawByWeek[currentWeekIndex];
  int? todayDayIndex = useWeekdaySlots && currentWeekdayIndex != null
      ? currentWeekdayIndex.clamp(DateTime.monday, DateTime.sunday) - 1
      : null;
  int? characterDayIndex;
  int? lastRunIndex;
  for (var d = 0; d < activeRaw.length; d++) {
    final stone = activeRaw[d];
    if (stone.kind != HomeStageStoneKind.run) {
      continue;
    }
    lastRunIndex = d;
    if (!stone.completed && todayDayIndex == null) {
      todayDayIndex = d;
    }
  }
  characterDayIndex = todayDayIndex ?? lastRunIndex ?? 0;

  final characterOrdinal =
      currentWeekIndex * kHomeStageDaysPerWeek + characterDayIndex;

  final sections = <HomeStageWeekSection>[];
  for (var w = 0; w < plan.weeks.length; w++) {
    final week = plan.weeks[w];
    final background = backgroundSequence.length > w
        ? backgroundSequence[w]
        : (backgroundSequence.isEmpty
              ? kHomeStageBackgroundAssets[w %
                    kHomeStageBackgroundAssets.length]
              : backgroundSequence[w % backgroundSequence.length]);
    final raw = rawByWeek[w];
    final stones = <HomeStageStone>[];
    for (var d = 0; d < raw.length; d++) {
      final stone = raw[d];
      final HomeStageStoneState state;
      if (stone.kind == HomeStageStoneKind.run) {
        if (stone.completed) {
          state = HomeStageStoneState.completed;
        } else if (w == currentWeekIndex && d == todayDayIndex) {
          state = HomeStageStoneState.current;
        } else if (useWeekdaySlots &&
            currentWeekdayIndex != null &&
            todayDayIndex != null &&
            (w < currentWeekIndex ||
                (w == currentWeekIndex && d < todayDayIndex))) {
          state = HomeStageStoneState.missed;
        } else {
          state = HomeStageStoneState.future;
        }
      } else {
        if (w == currentWeekIndex && d == todayDayIndex) {
          state = HomeStageStoneState.current;
        } else {
          final ordinal = w * kHomeStageDaysPerWeek + d;
          state = ordinal < characterOrdinal
              ? HomeStageStoneState.completed
              : HomeStageStoneState.future;
        }
      }
      stones.add(
        HomeStageStone(
          weekNumber: week.weekNumber,
          dayIndex: d,
          kind: stone.kind,
          state: state,
          scheduledWorkoutId: stone.scheduledWorkoutId,
          workoutTitle: stone.workoutTitle,
          dayLabel: stone.dayLabel,
        ),
      );
    }
    sections.add(
      HomeStageWeekSection(
        weekNumber: week.weekNumber,
        backgroundAsset: background,
        stones: stones,
      ),
    );
  }

  return HomeStageMapModel(
    sections: sections,
    currentWeekIndex: currentWeekIndex,
    todayDayIndex: todayDayIndex,
    characterDayIndex: characterDayIndex,
    currentStageId: HomeStageMapModel.stageId(
      currentWeekIndex,
      characterDayIndex,
    ),
  );
}

/// Builds one week's 7 raw stones keyed by real weekday slot (Mon=0..Sun=6).
///
/// Every slot always gets a weekday [dayLabel]. Run stones from
/// [week.workouts] are placed at their weekday's slot; if two workouts map
/// to the same weekday (e.g. a duplicated preferred-day cycle), the later one
/// is shifted forward to the next free slot, wrapping around the week. Any
/// slot left unclaimed by a run workout becomes a rest stone.
List<_RawStone> _weekdaySlottedRawStones({
  required BeginnerAdaptivePlanWeek week,
  required Set<String> completedScheduledWorkoutIds,
}) {
  final slots = List<_RawStone?>.filled(kHomeStageDaysPerWeek, null);
  for (final workout in week.workouts) {
    if (!isGeneratedPlanSession(workout)) {
      continue;
    }
    final id = homeStageScheduledWorkoutId(
      weekNumber: week.weekNumber,
      dayLabel: workout.dayLabel,
      title: workout.title,
    );
    var slot = _weekdaySlotIndexFor(workout.dayLabel);
    if (slot == null) {
      // Guarded by _planUsesWeekdayLabels, but stay defensive.
      continue;
    }
    var attempts = 0;
    while (slots[slot!] != null && attempts < kHomeStageDaysPerWeek) {
      slot = (slot + 1) % kHomeStageDaysPerWeek;
      attempts++;
    }
    if (slots[slot] != null) {
      // Week already has 7 run workouts claiming every slot; drop overflow.
      continue;
    }
    slots[slot] = _RawStone(
      kind: HomeStageStoneKind.run,
      completed: completedScheduledWorkoutIds.contains(id),
      dayLabel: kHomeStageWeekdayLabels[slot],
      scheduledWorkoutId: id,
      workoutTitle: workout.title,
    );
  }
  return [
    for (var d = 0; d < kHomeStageDaysPerWeek; d++)
      slots[d] ??
          _RawStone(
            kind: HomeStageStoneKind.rest,
            completed: false,
            dayLabel: kHomeStageWeekdayLabels[d],
            scheduledWorkoutId: null,
            workoutTitle: null,
          ),
  ];
}

/// Builds one week's 7 raw stones by workout position (fallback for
/// synthetic labels like `'Day 1'`), matching the original day-slot layout.
List<_RawStone> _positionalRawStones({
  required BeginnerAdaptivePlanWeek week,
  required Set<String> completedScheduledWorkoutIds,
}) {
  final rawStones = <_RawStone>[];
  for (var d = 0; d < kHomeStageDaysPerWeek; d++) {
    if (d < week.workouts.length) {
      final workout = week.workouts[d];
      if (isGeneratedPlanSession(workout)) {
        final id = homeStageScheduledWorkoutId(
          weekNumber: week.weekNumber,
          dayLabel: workout.dayLabel,
          title: workout.title,
        );
        rawStones.add(
          _RawStone(
            kind: HomeStageStoneKind.run,
            completed: completedScheduledWorkoutIds.contains(id),
            dayLabel: workout.dayLabel,
            scheduledWorkoutId: id,
            workoutTitle: workout.title,
          ),
        );
        continue;
      }
    }
    rawStones.add(
      const _RawStone(
        kind: HomeStageStoneKind.rest,
        completed: false,
        dayLabel: null,
        scheduledWorkoutId: null,
        workoutTitle: null,
      ),
    );
  }
  return rawStones;
}
