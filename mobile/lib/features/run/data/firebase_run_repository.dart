import '../domain/models/complete_run_result.dart';
import '../domain/models/cool_down_contract.dart';
import '../domain/models/local_run_completion_payload.dart';
import '../domain/models/pace_graph_snapshot.dart';
import '../domain/models/progression_display_model.dart';
import '../domain/models/run_activity_read_model.dart';
import '../domain/models/run_completion_error.dart';
import '../domain/models/run_completion_request_adapter.dart';
import '../domain/models/run_summary_read_model.dart';
import '../domain/models/run_summary_snapshot.dart';
import '../domain/repositories/run_repository.dart';
import '../domain/services/run_summary_scalar_mapper.dart';
import '../domain/services/xp_update_display_model_mapper.dart';
import 'static_run_repository.dart';

abstract interface class CompleteRunCallable {
  Future<Map<String, Object?>> call(Map<String, Object?> request);
}

/// Requests the server-computed cool-down stretch XP bonus. Mirrors
/// [CompleteRunCallable]'s shape; the same [CompleteRunCallableException]
/// type is used to report failures from either callable.
abstract interface class CompleteCoolDownCallable {
  Future<Map<String, Object?>> call(Map<String, Object?> request);
}

class CompleteRunCallableException implements Exception {
  const CompleteRunCallableException({
    required this.code,
    required this.message,
  });

  final String code;
  final String message;
}

/// A neutral, non-rendered run summary used for [CompleteRunResult]s that
/// only carry a cool-down XP bonus. The cool-down flow never displays this
/// summary — callers only consume `progressionDisplay` / `xpUpdate` via
/// [CompleteRunResult.mergeCoolDownBonus] — so every field is a harmless
/// placeholder rather than a real measurement.
const _coolDownBonusOnlySummary = RunSummarySnapshot(
  title: '--',
  dateLabel: '--',
  timeLabel: '--',
  distanceKm: '--',
  avgPace: '--',
  duration: '--',
  avgHeartRate: '--',
  calories: '--',
  routeName: '--',
  hasSufficientData: false,
  paceGraph: PaceGraphSnapshot.unavailable(),
);

class FirebaseRunRepository implements RunRepository {
  const FirebaseRunRepository({
    required this.callable,
    this.coolDownCallable,
    this.staticFallback = const StaticRunRepository(),
  });

  final CompleteRunCallable callable;
  final CompleteCoolDownCallable? coolDownCallable;
  final RunRepository staticFallback;

  @override
  Future<CompleteRunResult> completeRun(
    LocalRunCompletionPayload payload,
  ) async {
    final request = RunCompletionRequestAdapter.toBackendRequest(payload);

    final response = await callable.call(request).onError((error, stackTrace) {
      if (error is CompleteRunCallableException) {
        throw RunCompletionException(
          code: error.code,
          message: error.message,
          isRetryable: _isRetryableCallableCode(error.code),
        );
      }
      throw RunCompletionException(
        code: 'unknown',
        message: 'Run completion failed before the emulator responded.',
        isRetryable: true,
      );
    });

    return _CompleteRunResultMapper.fromCallableResponse(
      response,
    ).copyWith(clientRunSessionId: payload.clientRunSessionId);
  }

  @override
  Future<CompleteRunResult> completeCoolDown({
    required String activityId,
    required String clientRunSessionId,
  }) async {
    final coolDownCallable = this.coolDownCallable;
    if (coolDownCallable == null) {
      throw const RunCompletionException(
        code: 'unimplemented',
        message: 'Cool-down bonus is unavailable.',
        isRetryable: false,
      );
    }

    final request = <String, Object?>{
      'activityId': activityId,
      'clientRunSessionId': clientRunSessionId,
      'completedStretchCount': coolDownStretchStepCount,
      'completedAt': _toBackendIsoString(DateTime.now()),
    };

    final response = await coolDownCallable.call(request).onError((
      error,
      stackTrace,
    ) {
      if (error is CompleteRunCallableException) {
        throw RunCompletionException(
          code: error.code,
          message: error.message,
          isRetryable: _isRetryableCallableCode(error.code),
        );
      }
      throw RunCompletionException(
        code: 'unknown',
        message: 'Cool-down bonus failed before the service responded.',
        isRetryable: true,
      );
    });

    return _CompleteRunResultMapper.fromCoolDownCallableResponse(response);
  }

  @override
  Future<CompleteRunResult> loadLatestCompletionResult() {
    return staticFallback.loadLatestCompletionResult();
  }

  @override
  Future<RunActivityReadModel> loadLatestRunActivity() {
    return staticFallback.loadLatestRunActivity();
  }

  @override
  Future<RunSummaryReadModel> loadLatestRunSummary() {
    return staticFallback.loadLatestRunSummary();
  }

  bool _isRetryableCallableCode(String code) {
    return code == 'unavailable' ||
        code == 'deadline-exceeded' ||
        code == 'internal';
  }

  /// Formats [value] the same way [RunCompletionRequestAdapter] serializes
  /// timestamps for the backend: UTC with exactly millisecond precision. The
  /// server's payload validator rejects timestamps with microsecond
  /// fractional digits, so this normalizes away Dart's native microsecond
  /// precision before sending `completedAt`.
  static String _toBackendIsoString(DateTime value) {
    final utc = value.toUtc();
    final millisecondDate = DateTime.utc(
      utc.year,
      utc.month,
      utc.day,
      utc.hour,
      utc.minute,
      utc.second,
      utc.millisecond,
    );
    return millisecondDate.toIso8601String();
  }
}

class _CompleteRunResultMapper {
  const _CompleteRunResultMapper._();

  static CompleteRunResult fromCallableResponse(Map<String, Object?> response) {
    final summary = _readMap(response, 'runSummary');
    final progression = _readMap(response, 'progressionDisplay');
    final planCompletion = _readOptionalMap(response, 'planCompletion');
    final paceSeconds = _readInt(summary, 'averagePaceSecondsPerKm');
    final distanceMeters = _readInt(summary, 'distanceMeters');
    final durationSeconds = _readInt(summary, 'durationSeconds');
    final endedAt = _readDate(summary, 'endedAt');
    final scalar = const RunSummaryScalarMapper().map(
      completedAt: endedAt,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      averagePaceSecondsPerKm: paceSeconds,
      routeLabel: _readOptionalString(summary, 'routeLabel'),
    );
    final progressionDisplay = _buildProgressionDisplay(progression);

    return CompleteRunResult(
      activityId: _readString(response, 'activityId'),
      summaryId: _readString(response, 'summaryId'),
      progressionEventId: _readString(response, 'progressionEventId'),
      validationStatus: _readString(response, 'validationStatus'),
      summary: RunSummarySnapshot(
        title: scalar.title,
        dateLabel: scalar.dateLabel,
        timeLabel: scalar.timeLabel,
        distanceKm: scalar.distanceKm,
        avgPace: scalar.avgPace,
        duration: scalar.duration,
        avgHeartRate: '--',
        calories: scalar.calories,
        routeName: scalar.routeName,
        hasSufficientData: scalar.hasSufficientData,
        paceGraph: const PaceGraphSnapshot.unavailable(
          unavailableReason: 'backend_graph_data_unavailable',
        ),
      ),
      progressionDisplay: progressionDisplay,
      planCompletion: PlanCompletionResult(
        completed: _readOptionalBool(planCompletion, 'completed') ?? false,
        planEnrollmentId: _readOptionalString(
          planCompletion,
          'planEnrollmentId',
        ),
        scheduledWorkoutId: _readOptionalString(
          planCompletion,
          'scheduledWorkoutId',
        ),
      ),
      xpUpdate: XpUpdateDisplayModelMapper.fromProgression(progressionDisplay),
      message: _readString(response, 'message'),
    );
  }

  /// Builds the cool-down-only [CompleteRunResult] from the `completeCoolDown`
  /// callable response. There is no `runSummary` on this response — the
  /// result's `summary` is a neutral placeholder that callers never render;
  /// only `progressionDisplay` / `xpUpdate` are consumed, via
  /// [CompleteRunResult.mergeCoolDownBonus].
  static CompleteRunResult fromCoolDownCallableResponse(
    Map<String, Object?> response,
  ) {
    final progression = _readMap(response, 'progressionDisplay');
    final progressionDisplay = _buildProgressionDisplay(progression);

    return CompleteRunResult(
      activityId: _readString(response, 'activityId'),
      progressionEventId: _readString(response, 'coolDownProgressionEventId'),
      validationStatus: 'validated',
      summary: _coolDownBonusOnlySummary,
      progressionDisplay: progressionDisplay,
      xpUpdate: XpUpdateDisplayModelMapper.fromProgression(progressionDisplay),
      message:
          _readOptionalString(response, 'message') ??
          'Cool-down bonus processed.',
    );
  }

  /// Builds a fully-populated [ProgressionDisplayModel] from a backend
  /// `progressionDisplay` map, reading optional numeric fields leniently
  /// (absent or non-numeric values become `null` rather than throwing).
  static ProgressionDisplayModel _buildProgressionDisplay(
    Map<String, Object?> progression,
  ) {
    return ProgressionDisplayModel(
      xpDelta: _readInt(progression, 'xpDelta'),
      countsTowardLeaderboard: _readBool(
        progression,
        'countsTowardLeaderboard',
      ),
      status: _readString(progression, 'status'),
      reason: _readString(progression, 'reason'),
      totalXp: _readNullableInt(progression, 'totalXp'),
      level: _readNullableInt(progression, 'level'),
      divisionKey: _readOptionalString(progression, 'divisionKey'),
      previousTotalXp: _readNullableInt(progression, 'previousTotalXp'),
      previousLevel: _readNullableInt(progression, 'previousLevel'),
      previousLevelProgressPercent: _readNullableInt(
        progression,
        'previousLevelProgressPercent',
      ),
      levelProgressPercent: _readNullableInt(
        progression,
        'levelProgressPercent',
      ),
      xpToNextLevel: _readNullableInt(progression, 'xpToNextLevel'),
      nextLevelXp: _readNullableInt(progression, 'nextLevelXp'),
      streak: _readNullableInt(progression, 'streak'),
      previousStreak: _readNullableInt(progression, 'previousStreak'),
    );
  }

  static Map<String, Object?>? _readOptionalMap(
    Map<String, Object?> source,
    String key,
  ) {
    final value = source[key];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  static bool? _readOptionalBool(Map<String, Object?>? source, String key) {
    return source?[key] is bool ? source![key] as bool : null;
  }

  static Map<String, Object?> _readMap(
    Map<String, Object?> source,
    String key,
  ) {
    final value = source[key];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    throw const RunCompletionException(
      code: 'invalid-response',
      message: 'The emulator returned an invalid run completion response.',
      isRetryable: true,
    );
  }

  static String _readString(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw const RunCompletionException(
      code: 'invalid-response',
      message: 'The emulator returned an invalid run completion response.',
      isRetryable: true,
    );
  }

  static String? _readOptionalString(Map<String, Object?>? source, String key) {
    final value = source?[key];
    if (value == null) {
      return null;
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw const RunCompletionException(
      code: 'invalid-response',
      message: 'The emulator returned an invalid run completion response.',
      isRetryable: true,
    );
  }

  static int _readInt(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite) {
      return value.round();
    }
    throw const RunCompletionException(
      code: 'invalid-response',
      message: 'The emulator returned an invalid run completion response.',
      isRetryable: true,
    );
  }

  /// Reads a backend field that is a number, an explicit `null` (for example a
  /// max-level `xpToNextLevel`), or absent. Returns `null` for both the
  /// explicit null and the absent case so callers treat max level as "no next
  /// level" without inventing a value.
  static int? _readNullableInt(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite) {
      return value.round();
    }
    return null;
  }

  static bool _readBool(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is bool) {
      return value;
    }
    throw const RunCompletionException(
      code: 'invalid-response',
      message: 'The emulator returned an invalid run completion response.',
      isRetryable: true,
    );
  }

  static DateTime _readDate(Map<String, Object?> source, String key) {
    final value = DateTime.tryParse(_readString(source, key));
    if (value != null) {
      return value;
    }
    throw const RunCompletionException(
      code: 'invalid-response',
      message: 'The emulator returned an invalid run completion response.',
      isRetryable: true,
    );
  }
}
