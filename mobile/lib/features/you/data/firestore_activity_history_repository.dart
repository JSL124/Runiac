import 'package:cloud_firestore/cloud_firestore.dart';

import '../../auth/domain/runiac_auth_service.dart';
import '../../run/domain/models/cadence_analysis_series.dart';
import '../../run/domain/models/pace_analysis_series.dart';
import '../../run/domain/models/pace_graph_snapshot.dart';
import '../../run/domain/models/run_feed_publish_source.dart';
import '../../run/domain/models/run_summary_snapshot.dart';
import '../../run/domain/services/pace_graph_data_builder.dart';
import '../../run/domain/services/run_summary_scalar_mapper.dart';
import '../domain/models/activity_history_read_model.dart';
import '../domain/repositories/activity_history_repository.dart';
import 'firestore_run_summary_snapshot_decoder.dart';
import 'static_activity_history_repository.dart';

abstract interface class ActivityHistorySummaryDocumentReader {
  Future<List<ActivityHistorySummaryDocument>> loadRunSummaries({
    required String ownerUid,
    required int limit,
  });

  Future<List<ActivityHistorySummaryDocument>> loadActivities({
    required String ownerUid,
    required int limit,
  });
}

class ActivityHistorySummaryDocument {
  const ActivityHistorySummaryDocument({required this.id, required this.data});

  final String id;
  final Map<String, Object?> data;
}

class FirestoreActivityHistorySummaryDocumentReader
    implements ActivityHistorySummaryDocumentReader {
  FirestoreActivityHistorySummaryDocumentReader({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  @override
  Future<List<ActivityHistorySummaryDocument>> loadRunSummaries({
    required String ownerUid,
    required int limit,
  }) async {
    final snapshot = await _firestore
        .collection('runSummaries')
        .where('ownerUid', isEqualTo: ownerUid)
        .orderBy('endedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map(
          (document) => ActivityHistorySummaryDocument(
            id: document.id,
            data: Map<String, Object?>.from(document.data()),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ActivityHistorySummaryDocument>> loadActivities({
    required String ownerUid,
    required int limit,
  }) async {
    final snapshot = await _firestore
        .collection('activities')
        .where('ownerUid', isEqualTo: ownerUid)
        .orderBy('endedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map(
          (document) => ActivityHistorySummaryDocument(
            id: document.id,
            data: Map<String, Object?>.from(document.data()),
          ),
        )
        .toList(growable: false);
  }
}

class FirestoreActivityHistoryRepository implements ActivityHistoryRepository {
  FirestoreActivityHistoryRepository({
    required this.authRepository,
    ActivityHistorySummaryDocumentReader? reader,
    ActivityHistoryRepository? fallbackRepository,
    this.mapper = const RunSummaryScalarMapper(),
    this.limit = 30,
  }) : documentReader =
           reader ?? FirestoreActivityHistorySummaryDocumentReader(),
       fallbackRepository =
           fallbackRepository ?? StaticActivityHistoryRepository();

  final RuniacAuthRepository authRepository;
  final ActivityHistorySummaryDocumentReader documentReader;
  final ActivityHistoryRepository fallbackRepository;
  final int limit;
  final RunSummaryScalarMapper mapper;

  @override
  Future<ActivityHistoryReadModel> loadActivityHistory() async {
    final currentUser = authRepository.currentUser;
    if (currentUser == null) {
      return fallbackRepository.loadActivityHistory();
    }

    final summaryDocuments = await _loadSummariesSafely(currentUser.uid);
    final activityDocuments = await _loadActivitiesSafely(currentUser.uid);
    if (authRepository.currentUser?.uid != currentUser.uid) {
      throw StateError('Activity history owner changed during load.');
    }
    if (summaryDocuments == null && activityDocuments == null) {
      throw StateError('Both activity history queries failed.');
    }
    final activities = _dedupeByIdentity(<_MappedActivity>[
      ..._mapDocuments(
        currentUser.uid,
        summaryDocuments ?? const [],
        dateKeys: const ['endedAt', 'completedAt'],
        source: _ActivityHistoryDocumentSource.summary,
      ),
      ..._mapDocuments(
        currentUser.uid,
        activityDocuments ?? const [],
        dateKeys: const ['completedAt', 'endedAt'],
        source: _ActivityHistoryDocumentSource.activity,
      ),
    ])..sort((left, right) => right.endedAt.compareTo(left.endedAt));

    return ActivityHistoryReadModel(
      recentRuns: activities
          .map((activity) => activity.item)
          .take(3)
          .toList(growable: false),
      months: _groupByMonth(activities),
    );
  }

  Future<List<ActivityHistorySummaryDocument>?> _loadSummariesSafely(
    String ownerUid,
  ) async {
    try {
      return await documentReader.loadRunSummaries(
        ownerUid: ownerUid,
        limit: limit,
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<ActivityHistorySummaryDocument>?> _loadActivitiesSafely(
    String ownerUid,
  ) async {
    try {
      return await documentReader.loadActivities(
        ownerUid: ownerUid,
        limit: limit,
      );
    } catch (_) {
      return null;
    }
  }

  _MappedActivity? _mapDocument(
    String ownerUid,
    ActivityHistorySummaryDocument document, {
    required List<String> dateKeys,
    required _ActivityHistoryDocumentSource source,
  }) {
    final data = document.data;
    if (_readRequiredString(data, 'ownerUid') != ownerUid) {
      return null;
    }

    final endedAt = _readDateTimeFromAny(data, dateKeys);
    final distanceMeters = _readInt(data, 'distanceMeters');
    final durationSeconds = _readInt(data, 'durationSeconds');
    final averagePaceSecondsPerKm = _readInt(data, 'averagePaceSecondsPerKm');
    if (endedAt == null ||
        distanceMeters == null ||
        durationSeconds == null ||
        averagePaceSecondsPerKm == null) {
      return null;
    }

    final activityId = _readOptionalString(data, 'activityId') ?? document.id;
    final clientRunSessionId = _readOptionalString(data, 'clientRunSessionId');
    final scalar = mapper.map(
      completedAt: endedAt,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      averagePaceSecondsPerKm: averagePaceSecondsPerKm,
      routeLabel: _readOptionalString(data, 'routeLabel'),
    );
    final persistedTitle = _readOptionalString(data, 'title');
    final routeLabel = _readOptionalString(data, 'routeLabel');
    final title =
        persistedTitle == null ||
            persistedTitle == 'Completed Run' ||
            persistedTitle == routeLabel ||
            _isGeneratedRunTitle(persistedTitle)
        ? scalar.title
        : persistedTitle;
    final cadenceAnalysisSeries = _readCadenceAnalysisSeries(data);
    final details = source == _ActivityHistoryDocumentSource.summary
        ? const FirestoreRunSummarySnapshotDecoder().decode(data)
        : FirestoreRunSummaryDetails.empty;
    final summarySnapshot = RunSummarySnapshot(
      title: title,
      dateLabel: scalar.dateLabel,
      timeLabel: scalar.timeLabel,
      distanceKm: scalar.distanceKm,
      avgPace: scalar.avgPace,
      duration: scalar.duration,
      avgHeartRate: '--',
      calories: scalar.calories,
      routeName: scalar.routeName,
      hasSufficientData: scalar.hasSufficientData,
      paceAnalysisSeries: details.paceAnalysisSeries,
      cadenceAnalysisSeries: cadenceAnalysisSeries,
      elevationSeries: details.elevationSeries,
      paceGraph: _paceGraphFrom(
        details.paceAnalysisSeries,
        hasSufficientData: scalar.hasSufficientData,
        durationSeconds: durationSeconds,
        distanceMeters: distanceMeters,
        averagePaceSecondsPerKm: averagePaceSecondsPerKm,
      ),
      route: details.route,
    );
    return _MappedActivity(
      endedAt: endedAt,
      identityKey: clientRunSessionId != null && clientRunSessionId.isNotEmpty
          ? 'client:$clientRunSessionId'
          : 'activity:$activityId',
      item: ActivityHistoryItemReadModel(
        activityId: activityId,
        clientRunSessionId: clientRunSessionId,
        title: title,
        completedAtLabel: scalar.dateLabel,
        distanceLabel: '${scalar.distanceKm} km',
        distanceMeters: distanceMeters,
        paceLabel: scalar.avgPace,
        durationLabel: scalar.duration,
        timeLabel: scalar.timeLabel,
        routeNameLabel: scalar.routeName,
        hasSufficientData: scalar.hasSufficientData,
        cadenceAnalysisSeries: cadenceAnalysisSeries,
        summarySnapshot: summarySnapshot,
        isTrustedPersistedRoutePreview: details.hasValidPersistedRoutePreview,
        feedPublishSource: _feedPublishSourceFor(
          data,
          activityId: activityId,
          cacheIdentity: clientRunSessionId,
          hasSufficientData: scalar.hasSufficientData,
          source: source,
        ),
      ),
    );
  }

  /// Rebuilds the Pace Over Time graph from the persisted analysis series.
  ///
  /// A `runSummaries` document stores `paceAnalysisSeries` but no rendered
  /// graph, so a run reopened from history has to derive one the same way
  /// `StaticRunRepository` does at completion time. Without this the summary
  /// screen keeps the [RunSummarySnapshot] default of
  /// [PaceGraphSnapshot.unavailable] and shows the low-data guard even for
  /// runs that carry a complete series.
  PaceGraphSnapshot _paceGraphFrom(
    PaceAnalysisSeries? series, {
    required bool hasSufficientData,
    required int durationSeconds,
    required int distanceMeters,
    required int averagePaceSecondsPerKm,
  }) {
    if (!hasSufficientData || series == null) {
      return const PaceGraphSnapshot.unavailable();
    }
    return const PaceGraphDataBuilder().build(
      samples: [
        for (final sample in series.samples)
          if (sample.status == PaceAnalysisSampleStatus.accepted)
            PaceGraphSample(
              elapsedSeconds: sample.elapsedSeconds,
              paceSecondsPerKm: sample.paceSecondsPerKm,
              cumulativeDistanceMeters: sample.cumulativeDistanceMeters.round(),
            ),
      ],
      durationSeconds: durationSeconds,
      distanceMeters: distanceMeters,
      averagePaceSecondsPerKm: averagePaceSecondsPerKm,
    );
  }

  bool _isGeneratedRunTitle(String title) {
    return RegExp(
      r'^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) '
      r'(Morning|Afternoon|Evening|Night) Run$',
    ).hasMatch(title);
  }

  List<_MappedActivity> _mapDocuments(
    String ownerUid,
    List<ActivityHistorySummaryDocument> documents, {
    required List<String> dateKeys,
    required _ActivityHistoryDocumentSource source,
  }) {
    return documents
        .map(
          (document) => _mapDocument(
            ownerUid,
            document,
            dateKeys: dateKeys,
            source: source,
          ),
        )
        .nonNulls
        .toList(growable: false);
  }

  List<_MappedActivity> _dedupeByIdentity(List<_MappedActivity> activities) {
    final byIdentity = <String, _MappedActivity>{};
    for (final activity in activities) {
      final existing = byIdentity[activity.identityKey];
      if (existing == null) {
        byIdentity[activity.identityKey] = activity;
        continue;
      }
      byIdentity[activity.identityKey] = existing.mergeFeedPublishSource(
        activity.item.feedPublishSource,
      );
    }
    return byIdentity.values.toList(growable: false);
  }

  RunFeedPublishSource _feedPublishSourceFor(
    Map<String, Object?> data, {
    required String activityId,
    required String? cacheIdentity,
    required bool hasSufficientData,
    required _ActivityHistoryDocumentSource source,
  }) {
    if (!hasSufficientData) {
      return const RunFeedPublishSource.disabled(
        FeedPublishDisabledReason.insufficientData,
      );
    }
    if (activityId.startsWith('local-') || activityId.startsWith('local_')) {
      return const RunFeedPublishSource.disabled(
        FeedPublishDisabledReason.localOnly,
      );
    }
    if (source == _ActivityHistoryDocumentSource.summary) {
      return const RunFeedPublishSource.disabled(
        FeedPublishDisabledReason.orphanSummary,
      );
    }
    if (_readOptionalString(data, 'status') != 'validated' ||
        _readOptionalString(data, 'validationStatus') != 'validated') {
      return const RunFeedPublishSource.disabled(
        FeedPublishDisabledReason.notValidated,
      );
    }
    return RunFeedPublishSource.enabled(
      activityId: activityId,
      cacheIdentity: cacheIdentity,
    );
  }

  DateTime? _readDateTimeFromAny(
    Map<String, Object?> source,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _readDateTime(source, key);
      if (value != null) {
        return value;
      }
    }
    return null;
  }

  List<ActivityHistoryMonthReadModel> _groupByMonth(
    List<_MappedActivity> activities,
  ) {
    final monthBuckets = <String, List<ActivityHistoryItemReadModel>>{};
    for (final activity in activities) {
      final label = _monthLabel(activity.endedAt);
      monthBuckets
          .putIfAbsent(label, () => <ActivityHistoryItemReadModel>[])
          .add(activity.item);
    }

    return monthBuckets.entries
        .map(
          (entry) => ActivityHistoryMonthReadModel(
            label: entry.key,
            activities: entry.value,
          ),
        )
        .toList(growable: false);
  }

  String _monthLabel(DateTime value) {
    final local = value.toLocal();
    return '${_monthName(local.month)} ${local.year}';
  }

  String _monthName(int month) {
    return switch (month) {
      DateTime.january => 'January',
      DateTime.february => 'February',
      DateTime.march => 'March',
      DateTime.april => 'April',
      DateTime.may => 'May',
      DateTime.june => 'June',
      DateTime.july => 'July',
      DateTime.august => 'August',
      DateTime.september => 'September',
      DateTime.october => 'October',
      DateTime.november => 'November',
      DateTime.december => 'December',
      _ => 'Unknown',
    };
  }

  String? _readRequiredString(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  String? _readOptionalString(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value == null) {
      return null;
    }
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
    return null;
  }

  int? _readInt(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite) {
      return value.round();
    }
    return null;
  }

  double? _readDouble(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is num && value.isFinite) {
      return value.toDouble();
    }
    return null;
  }

  Map<String, Object?>? _readMap(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  List<Object?> _readList(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is List) {
      return value;
    }
    return const <Object?>[];
  }

  T? _enumByName<T extends Enum>(List<T> values, Object? raw) {
    if (raw is! String) {
      return null;
    }
    for (final value in values) {
      if (value.name == raw) {
        return value;
      }
    }
    return null;
  }

  CadenceAnalysisSeries? _readCadenceAnalysisSeries(
    Map<String, Object?> source,
  ) {
    final cadence = _readMap(source, 'cadenceAnalysisSeries');
    if (cadence == null) {
      return null;
    }
    final cadenceSource = _enumByName(
      CadenceAnalysisSource.values,
      cadence['source'],
    );
    final confidence = _enumByName(
      CadenceAnalysisConfidence.values,
      cadence['confidence'],
    );
    if (cadenceSource == null || confidence == null) {
      return null;
    }
    final samples = _readList(
      cadence,
      'samples',
    ).map(_readCadenceSample).nonNulls.toList(growable: false);
    try {
      return CadenceAnalysisSeries(
        source: cadenceSource,
        confidence: confidence,
        samples: samples,
      );
    } on ArgumentError {
      return null;
    }
  }

  CadenceAnalysisSample? _readCadenceSample(Object? value) {
    final sample = value is Map<String, Object?>
        ? value
        : value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : null;
    if (sample == null) {
      return null;
    }
    final elapsedSeconds = _readInt(sample, 'elapsedSeconds');
    final cadenceSpm = _readDouble(sample, 'cadenceSpm');
    final status = _enumByName(
      CadenceAnalysisSampleStatus.values,
      sample['status'],
    );
    final rejectionReason =
        _enumByName(
          CadenceAnalysisSampleRejectionReason.values,
          sample['rejectionReason'],
        ) ??
        CadenceAnalysisSampleRejectionReason.none;
    if (elapsedSeconds == null || cadenceSpm == null || status == null) {
      return null;
    }
    try {
      return CadenceAnalysisSample(
        elapsedSeconds: elapsedSeconds,
        cadenceSpm: cadenceSpm,
        status: status,
        rejectionReason: rejectionReason,
      );
    } on ArgumentError {
      return null;
    }
  }

  DateTime? _readDateTime(Map<String, Object?> source, String key) {
    final value = source[key];
    if (value is DateTime) {
      return value;
    }
    if (value is Timestamp) {
      return value.toDate();
    }
    if (value is String) {
      return DateTime.tryParse(value);
    }
    return null;
  }
}

class _MappedActivity {
  const _MappedActivity({
    required this.endedAt,
    required this.identityKey,
    required this.item,
  });

  final DateTime endedAt;
  final String identityKey;
  final ActivityHistoryItemReadModel item;

  _MappedActivity mergeFeedPublishSource(RunFeedPublishSource candidate) {
    final current = item.feedPublishSource;
    if (!candidate.isPublishable &&
        (current.isPublishable ||
            current.disabledReason !=
                FeedPublishDisabledReason.orphanSummary)) {
      return this;
    }
    return _MappedActivity(
      endedAt: endedAt,
      identityKey: identityKey,
      item: item.copyWith(feedPublishSource: candidate),
    );
  }
}

enum _ActivityHistoryDocumentSource { summary, activity }
