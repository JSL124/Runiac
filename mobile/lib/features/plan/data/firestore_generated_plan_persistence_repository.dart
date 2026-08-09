import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/beginner_adaptive_plan_snapshot.dart';
import '../domain/models/plan_family.dart';
import '../domain/repositories/generated_plan_persistence_repository.dart';

/// Stores and reloads the runner's generated plan.
///
/// The plan is regenerated deterministically from the onboarding answers, so
/// what is persisted is the *result plus the runner's edits* — rescheduled
/// days, completed sessions — which cannot be recovered by regenerating.
///
/// [GeneratedPlanUpdatedAtFactory] exists so the timestamp is injectable:
/// production uses the server timestamp, tests use a fixed clock.
typedef GeneratedPlanUpdatedAtFactory = Object Function();

abstract interface class GeneratedPlanDocumentStore {
  Future<Map<String, Object?>?> loadGeneratedPlan({required String uid});

  Future<void> saveGeneratedPlan({
    required String uid,
    required Map<String, Object?> data,
    bool resetCreatedAt = false,
  });
}

class FirestoreGeneratedPlanDocumentStore
    implements GeneratedPlanDocumentStore {
  FirestoreGeneratedPlanDocumentStore({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<Map<String, Object?>?> loadGeneratedPlan({required String uid}) async {
    final snapshot = await _firestore
        .collection('generatedPlans')
        .doc(uid)
        .get();
    return snapshot.data();
  }

  @override
  Future<void> saveGeneratedPlan({
    required String uid,
    required Map<String, Object?> data,
    bool resetCreatedAt = false,
  }) async {
    final planRef = _firestore.collection('generatedPlans').doc(uid);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(planRef);
      final nextData = <String, Object?>{...data};
      if (resetCreatedAt ||
          !snapshot.exists ||
          snapshot.data()?['createdAt'] == null) {
        nextData['createdAt'] = data['updatedAt'];
      }
      transaction.set(planRef, nextData, SetOptions(merge: true));
    });
  }
}

class FirestoreGeneratedPlanPersistenceRepository
    implements GeneratedPlanPersistenceRepository {
  FirestoreGeneratedPlanPersistenceRepository({
    GeneratedPlanDocumentStore? documentStore,
    GeneratedPlanUpdatedAtFactory? updatedAt,
  }) : _documentStore = documentStore ?? FirestoreGeneratedPlanDocumentStore(),
       _updatedAt = updatedAt ?? FieldValue.serverTimestamp;

  final GeneratedPlanDocumentStore _documentStore;
  final GeneratedPlanUpdatedAtFactory _updatedAt;

  @override
  Future<BeginnerAdaptivePlanSnapshot?> loadGeneratedPlan({
    required String uid,
  }) async {
    final data = await _documentStore.loadGeneratedPlan(uid: uid);
    if (data == null) {
      return null;
    }
    return _planFromFirestore(data);
  }

  @override
  Future<void> saveGeneratedPlan({
    required String uid,
    required BeginnerAdaptivePlanSnapshot plan,
    bool resetCreatedAt = false,
  }) {
    return _documentStore.saveGeneratedPlan(
      uid: uid,
      data: _planToFirestore(plan, updatedAt: _updatedAt()),
      resetCreatedAt: resetCreatedAt,
    );
  }
}

Map<String, Object?> _planToFirestore(
  BeginnerAdaptivePlanSnapshot plan, {
  required Object updatedAt,
}) {
  return <String, Object?>{
    'planId': plan.id,
    'planKind': plan.planKind.name,
    'title': plan.title,
    'subtitle': plan.subtitle,
    'sourceLabel': plan.sourceLabel,
    if (plan.startsOnDate != null) 'startsOnDate': plan.startsOnDate,
    'durationWeeks': plan.durationWeeks,
    'safetyBand': plan.safetyBand.name,
    'templateKind': plan.templateKind.name,
    'family': plan.family?.name,
    'familyCategory': plan.familyCategory?.name,
    'familyReason': plan.familyReason,
    'supportStyleLabel': plan.supportStyleLabel,
    'weeklyFrequencyLabel': plan.weeklyFrequencyLabel,
    'preferredScheduleLabel': plan.preferredScheduleLabel,
    'sessionDurationLabel': plan.sessionDurationLabel,
    'safetyNote': plan.safetyNote,
    'clientDisplayStatus': plan.clientDisplayStatus.name,
    'weeks': [
      for (final week in plan.weeks)
        <String, Object?>{
          'weekNumber': week.weekNumber,
          'title': week.title,
          'focus': week.focus,
          'workouts': [
            for (final workout in week.workouts)
              <String, Object?>{
                'dayLabel': workout.dayLabel,
                'title': workout.title,
                'durationMinutes': workout.durationMinutes,
                'kind': workout.kind.name,
                'intensity': workout.intensity.name,
                'description': workout.description,
                'steps': workout.steps,
                'supportiveNote': workout.supportiveNote,
                'detail': _detailToFirestore(workout.detail),
                if (workout.scheduleTimeLabel != null)
                  'scheduleTimeLabel': workout.scheduleTimeLabel,
              },
          ],
        },
    ],
    'updatedAt': updatedAt,
  };
}

Map<String, Object?> _detailToFirestore(BeginnerAdaptiveWorkoutDetail detail) {
  return <String, Object?>{
    'metrics': [
      for (final metric in detail.metrics)
        <String, Object?>{'label': metric.label, 'value': metric.value},
    ],
    'breakdown': [
      for (final step in detail.breakdown)
        <String, Object?>{
          'kind': step.kind.name,
          'title': step.title,
          'detail': step.detail,
        },
    ],
    'effortGuide': detail.effortGuide,
    'coachNotes': detail.coachNotes,
  };
}

BeginnerAdaptivePlanSnapshot _planFromFirestore(Map<String, Object?> data) {
  return BeginnerAdaptivePlanSnapshot(
    id: _string(data['planId']),
    title: _string(data['title']),
    subtitle: _string(data['subtitle']),
    planKind: _enumByName(
      BeginnerAdaptivePlanKind.values,
      _string(data['planKind']),
    ),
    sourceLabel: _string(data['sourceLabel']),
    startsOnDate: _startsOnDateFromFirestore(data),
    durationWeeks: _int(data['durationWeeks']),
    safetyBand: _enumByName(
      BeginnerPlanSafetyBand.values,
      _string(data['safetyBand']),
    ),
    templateKind: _enumByName(
      BeginnerPlanTemplateKind.values,
      _string(data['templateKind']),
    ),
    family: _nullableEnumByName(PlanFamily.values, data['family']),
    familyCategory: _nullableEnumByName(
      PlanFamilyCategory.values,
      data['familyCategory'],
    ),
    familyReason: _string(data['familyReason']),
    supportStyleLabel: _string(data['supportStyleLabel']),
    weeklyFrequencyLabel: _string(data['weeklyFrequencyLabel']),
    preferredScheduleLabel: _string(data['preferredScheduleLabel']),
    sessionDurationLabel: _string(data['sessionDurationLabel']),
    safetyNote: _string(data['safetyNote']),
    clientDisplayStatus: _enumByName(
      BeginnerAdaptivePlanClientDisplayStatus.values,
      _string(data['clientDisplayStatus']),
    ),
    weeks: [
      for (final week in _maps(data['weeks']))
        BeginnerAdaptivePlanWeek(
          weekNumber: _int(week['weekNumber']),
          title: _string(week['title']),
          focus: _string(week['focus']),
          workouts: [
            for (final workout in _maps(week['workouts']))
              BeginnerAdaptiveWorkout(
                dayLabel: _string(workout['dayLabel']),
                title: _string(workout['title']),
                durationMinutes: _int(workout['durationMinutes']),
                kind: _enumByName(
                  BeginnerWorkoutKind.values,
                  _string(workout['kind']),
                ),
                intensity: _enumByName(
                  BeginnerPlanIntensity.values,
                  _string(workout['intensity']),
                ),
                description: _string(workout['description']),
                steps: _strings(workout['steps']),
                supportiveNote: _string(workout['supportiveNote']),
                detail: _detailFromFirestore(_map(workout['detail'])),
                scheduleTimeLabel: _nullableString(
                  workout['scheduleTimeLabel'],
                ),
              ),
          ],
        ),
    ],
  );
}

String? _startsOnDateFromFirestore(Map<String, Object?> data) {
  final explicitStart = _nullableString(data['startsOnDate']);
  if (explicitStart != null) {
    return explicitStart;
  }
  final createdAt = data['createdAt'];
  if (createdAt is Timestamp) {
    return generatedPlanDateLabel(createdAt.toDate().toLocal());
  }
  if (createdAt is DateTime) {
    return generatedPlanDateLabel(createdAt.toLocal());
  }
  final parsed = DateTime.tryParse(_string(createdAt));
  if (parsed != null) {
    return generatedPlanDateLabel(parsed);
  }
  return null;
}

BeginnerAdaptiveWorkoutDetail _detailFromFirestore(Map<String, Object?> data) {
  return BeginnerAdaptiveWorkoutDetail(
    metrics: [
      for (final metric in _maps(data['metrics']))
        BeginnerAdaptiveWorkoutMetric(
          label: _string(metric['label']),
          value: _string(metric['value']),
        ),
    ],
    breakdown: [
      for (final step in _maps(data['breakdown']))
        BeginnerAdaptiveWorkoutBreakdownStep(
          kind: _enumByName(
            BeginnerAdaptiveWorkoutBreakdownStepKind.values,
            _string(step['kind']),
          ),
          title: _string(step['title']),
          detail: _string(step['detail']),
        ),
    ],
    effortGuide: _string(data['effortGuide']),
    coachNotes: _strings(data['coachNotes']),
  );
}

T _enumByName<T extends Enum>(List<T> values, String name) {
  return values.firstWhere((value) => value.name == name);
}

T? _nullableEnumByName<T extends Enum>(List<T> values, Object? value) {
  if (value is! String || value.isEmpty) {
    return null;
  }
  return _enumByName(values, value);
}

String _string(Object? value) {
  return value is String ? value : '';
}

String? _nullableString(Object? value) {
  return value is String && value.isNotEmpty ? value : null;
}

int _int(Object? value) {
  return value is int ? value : 0;
}

List<String> _strings(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final item in value)
      if (item is String) item,
  ];
}

List<Map<String, Object?>> _maps(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [for (final item in value) _map(item)];
}

Map<String, Object?> _map(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}
