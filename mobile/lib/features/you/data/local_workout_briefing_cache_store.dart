import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/workout_briefing_agent.dart';

/// Sibling of the activity-feedback cache rather than a reuse of it: that
/// store's encode/decode hardcodes the four run-shaped section keys, so sharing
/// it would mean writing the wrong key names to disk or editing a file that
/// belongs to an already-shipped capsule.
class LocalWorkoutBriefingCacheEntry {
  const LocalWorkoutBriefingCacheEntry({
    required this.cachedAt,
    required this.sections,
  });

  final DateTime cachedAt;
  final WorkoutBriefingSections sections;

  String encode() {
    return jsonEncode(<String, Object?>{
      'cachedAt': cachedAt.toUtc().toIso8601String(),
      'sections': <String, Object?>{
        'todaySession': sections.todaySession,
        'whyItHelps': sections.whyItHelps,
        'howItFeels': sections.howItFeels,
        'beforeYouStart': sections.beforeYouStart,
      },
    });
  }

  static LocalWorkoutBriefingCacheEntry? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Briefing cache is not an object.');
      }
      final cachedAt = DateTime.tryParse('${decoded['cachedAt']}');
      final sections = decoded['sections'];
      if (cachedAt == null || sections is! Map<String, Object?>) {
        throw const FormatException('Briefing cache has an invalid shape.');
      }
      final todaySession = sections['todaySession'];
      final whyItHelps = sections['whyItHelps'];
      final howItFeels = sections['howItFeels'];
      final beforeYouStart = sections['beforeYouStart'];
      if (todaySession is! String ||
          whyItHelps is! String ||
          howItFeels is! String ||
          beforeYouStart is! String) {
        throw const FormatException('Briefing cache sections are invalid.');
      }
      return LocalWorkoutBriefingCacheEntry(
        cachedAt: cachedAt.toUtc(),
        sections: WorkoutBriefingSections(
          todaySession: todaySession,
          whyItHelps: whyItHelps,
          howItFeels: howItFeels,
          beforeYouStart: beforeYouStart,
        ),
      );
    } on TypeError {
      throw const FormatException('Briefing cache has invalid types.');
    }
  }
}

abstract interface class LocalWorkoutBriefingCacheStore {
  Future<LocalWorkoutBriefingCacheEntry?> load({
    required String ownerUid,
    required String workoutIdentity,
  });

  Future<void> save({
    required String ownerUid,
    required String workoutIdentity,
    required LocalWorkoutBriefingCacheEntry entry,
  });

  Future<void> remove({
    required String ownerUid,
    required String workoutIdentity,
  });
}

class SharedPreferencesLocalWorkoutBriefingCacheStore
    implements LocalWorkoutBriefingCacheStore {
  const SharedPreferencesLocalWorkoutBriefingCacheStore({
    this.keyPrefix = 'runiac.workoutBriefingCache.v1.',
  });

  final String keyPrefix;

  @override
  Future<LocalWorkoutBriefingCacheEntry?> load({
    required String ownerUid,
    required String workoutIdentity,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return LocalWorkoutBriefingCacheEntry.tryDecode(
      preferences.getString(_key(ownerUid, workoutIdentity)),
    );
  }

  @override
  Future<void> save({
    required String ownerUid,
    required String workoutIdentity,
    required LocalWorkoutBriefingCacheEntry entry,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final didPersist = await preferences.setString(
      _key(ownerUid, workoutIdentity),
      entry.encode(),
    );
    if (!didPersist) {
      throw StateError('Workout briefing cache write failed.');
    }
  }

  @override
  Future<void> remove({
    required String ownerUid,
    required String workoutIdentity,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(ownerUid, workoutIdentity));
  }

  String _key(String ownerUid, String workoutIdentity) {
    return '$keyPrefix${_keyPart(ownerUid)}.${_keyPart(workoutIdentity)}';
  }

  String _keyPart(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }
}
