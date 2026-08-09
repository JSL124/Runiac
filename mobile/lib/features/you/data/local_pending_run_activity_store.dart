import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../run/domain/models/cadence_analysis_series.dart';
import '../../run/domain/models/complete_run_result.dart';
import '../../run/domain/models/elevation_analysis_series.dart';
import '../../run/domain/models/local_run_completion_payload.dart';
import '../../run/domain/models/pace_analysis_series.dart';
import '../../run/domain/models/progression_display_model.dart';
import '../../run/domain/models/run_location_sample.dart';
import '../../run/domain/models/run_route_snapshot.dart';
import '../../run/domain/models/run_summary_snapshot.dart';
import '../../run/domain/models/xp_update_display_model.dart';
import '../../run/domain/services/pace_graph_data_builder.dart';

part 'local_pending_run_activity.dart';
part 'local_pending_run_activity_codec.dart';

abstract interface class LocalPendingRunActivityStore {
  Future<List<LocalPendingRunActivity>> load();

  Future<void> save(List<LocalPendingRunActivity> activities);
}

class MemoryLocalPendingRunActivityStore
    implements LocalPendingRunActivityStore {
  List<LocalPendingRunActivity> _activities = const <LocalPendingRunActivity>[];

  @override
  Future<List<LocalPendingRunActivity>> load() async {
    return List<LocalPendingRunActivity>.of(_activities);
  }

  @override
  Future<void> save(List<LocalPendingRunActivity> activities) async {
    _activities = List<LocalPendingRunActivity>.of(activities);
  }
}

class SharedPreferencesLocalPendingRunActivityStore
    implements LocalPendingRunActivityStore {
  const SharedPreferencesLocalPendingRunActivityStore({
    this.key = 'runiac.pendingRunActivities.v1',
  });

  final String key;

  @override
  Future<List<LocalPendingRunActivity>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final rawRecords = preferences.getStringList(key) ?? const <String>[];
    return rawRecords
        .map(LocalPendingRunActivity.tryDecode)
        .nonNulls
        .toList(growable: false);
  }

  @override
  Future<void> save(List<LocalPendingRunActivity> activities) async {
    final preferences = await SharedPreferences.getInstance();
    final didPersist = await preferences.setStringList(
      key,
      activities.map((activity) => activity.encode()).toList(growable: false),
    );
    if (!didPersist) {
      throw StateError('Pending run activity storage write failed.');
    }
  }
}
