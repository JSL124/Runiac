// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import '../../run/domain/models/run_activity_display_model.dart';
import '../../run/domain/models/run_summary_snapshot.dart';
import '../data/static_activity_history_repository.dart';
import '../domain/models/activity_history_read_model.dart';
import '../domain/repositories/activity_history_repository.dart';
import 'current_session_activity_history.dart';
import 'data/activity_history_demo_snapshots.dart';
import 'data/you_overview_demo_snapshots.dart';

/// Decides what the activity history shows, from three sources that can
/// disagree.
///
/// A run may exist only on the backend, only on this device (finished offline
/// and not yet synced), or in both. This controller merges them into one
/// ordered list without duplicates, so a run does not appear twice the moment
/// its sync lands.
///
/// It also picks the demo history when the app runs without a backend, which is
/// why the static snapshots are imported here rather than in the screen — the
/// widget layer stays unaware of which source it is rendering.
class ActivityHistoryDisplayController extends ChangeNotifier {
  ActivityHistoryDisplayController({
    required this.repository,
    CurrentSessionActivityHistoryStore? activityHistoryStore,
  }) : _activityHistoryStore = activityHistoryStore;

  final ActivityHistoryRepository repository;
  CurrentSessionActivityHistoryStore? _activityHistoryStore;
  ActivityHistoryReadModel? _loadedActivityHistory;
  var _loadFailed = false;
  var _loadRequestId = 0;
  var _disposed = false;

  bool get loadFailed => _loadFailed;
  bool get initialLoadPending =>
      !_usesStaticRepository && _loadedActivityHistory == null && !_loadFailed;

  Future<void> load() async {
    final requestId = ++_loadRequestId;
    _loadFailed = false;
    _notifyIfActive();

    try {
      final history = await repository.loadActivityHistory();
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _loadedActivityHistory = history;
      _loadFailed = false;
      _reconcileLoadedRemoteWithStore();
      _notifyIfActive();
    } catch (_) {
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _loadFailed = true;
      _notifyIfActive();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadRequestId += 1;
    super.dispose();
  }

  void attachActivityHistoryStore(CurrentSessionActivityHistoryStore store) {
    if (identical(_activityHistoryStore, store)) {
      return;
    }
    _activityHistoryStore = store;
    _reconcileLoadedRemoteWithStore();
  }

  List<RunActivityDisplayModel> recentRuns(
    CurrentSessionActivityHistoryStore activityHistoryStore,
  ) {
    final repositoryRuns = _repositoryRecentRuns();
    return activityHistoryStore.recentRunsWithFallback(repositoryRuns);
  }

  List<ActivityHistoryMonth> months(
    CurrentSessionActivityHistoryStore activityHistoryStore,
  ) {
    final repositoryMonths = _repositoryMonths();
    return _dedupeMonths(
      activityHistoryStore.activityHistoryWithFallback(repositoryMonths),
    );
  }

  void _reconcileLoadedRemoteWithStore() {
    final store = _activityHistoryStore;
    if (store == null ||
        _usesStaticRepository ||
        _loadedActivityHistory == null) {
      return;
    }
    final repositoryActivities = <RunActivityDisplayModel>[
      ..._repositoryRecentRuns(),
      for (final month in _repositoryMonths()) ...month.activities,
    ];
    store.reconcileWithRemote(repositoryActivities);
  }

  List<RunActivityDisplayModel> _repositoryRecentRuns() {
    final history = _loadedActivityHistory;
    if (_usesStaticRepository) {
      return youProgressSnapshot.runs;
    }
    if (history == null || history.recentRuns.isEmpty) {
      return const <RunActivityDisplayModel>[];
    }
    return history.recentRuns
        .map(_activityItemToDisplay)
        .toList(growable: false);
  }

  List<ActivityHistoryMonth> _repositoryMonths() {
    final history = _loadedActivityHistory;
    if (_usesStaticRepository) {
      return activityHistoryDisplayData;
    }
    if (history == null || history.months.isEmpty) {
      return const <ActivityHistoryMonth>[];
    }
    return history.months
        .map(
          (month) => ActivityHistoryMonth(
            label: month.label,
            activities: month.activities
                .map(_activityItemToDisplay)
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
  }

  bool get _usesStaticRepository =>
      repository is StaticActivityHistoryRepository;

  RunActivityDisplayModel _activityItemToDisplay(
    ActivityHistoryItemReadModel item,
  ) {
    final routeName = item.routeNameLabel.isEmpty
        ? 'Private route'
        : item.routeNameLabel;
    final timeLabel = item.timeLabel.isEmpty ? '--' : item.timeLabel;
    final duration = item.durationLabel.isEmpty ? '--' : item.durationLabel;
    final pace = item.paceLabel.isEmpty ? '--' : item.paceLabel;
    final summary =
        item.summarySnapshot ??
        RunSummarySnapshot(
          title: item.title,
          dateLabel: item.completedAtLabel,
          timeLabel: timeLabel,
          distanceKm: _distanceKmValue(item.distanceLabel),
          avgPace: pace,
          duration: duration,
          avgHeartRate: '--',
          calories: '--',
          routeName: routeName,
          hasSufficientData: item.hasSufficientData,
          cadenceAnalysisSeries: item.cadenceAnalysisSeries,
        );

    return RunActivityDisplayModel(
      activityId: item.activityId,
      clientRunSessionId: item.clientRunSessionId,
      title: item.title,
      timeAgoLabel: item.completedAtLabel,
      distanceLabel: item.distanceLabel,
      distanceMeters: item.distanceMeters,
      paceLabel: pace,
      durationLabel: duration,
      summary: summary,
      isTrustedPersistedRoutePreview: item.isTrustedPersistedRoutePreview,
      feedPublishSource: item.feedPublishSource,
    );
  }

  String _distanceKmValue(String distanceLabel) {
    return distanceLabel.replaceAll(
      RegExp(r'\s*km$', caseSensitive: false),
      '',
    );
  }

  List<ActivityHistoryMonth> _dedupeMonths(List<ActivityHistoryMonth> months) {
    final seenIds = <String>{};
    return months
        .map((month) {
          final activities = <RunActivityDisplayModel>[];
          for (final activity in month.activities) {
            final activityId = activity.activityId;
            final clientRunSessionId = activity.clientRunSessionId;
            final identityKey =
                clientRunSessionId != null && clientRunSessionId.isNotEmpty
                ? 'client:$clientRunSessionId'
                : activityId != null && activityId.isNotEmpty
                ? 'activity:$activityId'
                : null;
            if (identityKey != null && !seenIds.add(identityKey)) {
              continue;
            }
            activities.add(activity);
          }
          return ActivityHistoryMonth(
            label: month.label,
            activities: activities,
          );
        })
        .where((month) => month.activities.isNotEmpty)
        .toList(growable: false);
  }

  void _notifyIfActive() {
    if (_disposed) {
      return;
    }
    notifyListeners();
  }
}
