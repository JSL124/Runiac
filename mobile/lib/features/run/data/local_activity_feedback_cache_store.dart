import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/activity_feedback_agent.dart';

class LocalActivityFeedbackCacheEntry {
  const LocalActivityFeedbackCacheEntry({
    required this.cachedAt,
    required this.sections,
  });

  final DateTime cachedAt;
  final ActivityFeedbackSections sections;

  String encode() {
    return jsonEncode(<String, Object?>{
      'cachedAt': cachedAt.toUtc().toIso8601String(),
      'sections': <String, Object?>{
        'summary': sections.summary,
        'wentWell': sections.wentWell,
        'improve': sections.improve,
        'nextFocus': sections.nextFocus,
      },
    });
  }

  static LocalActivityFeedbackCacheEntry? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('Feedback cache is not an object.');
      }
      final cachedAt = DateTime.tryParse('${decoded['cachedAt']}');
      final sections = decoded['sections'];
      if (cachedAt == null || sections is! Map<String, Object?>) {
        throw const FormatException('Feedback cache has an invalid shape.');
      }
      final summary = sections['summary'];
      final wentWell = sections['wentWell'];
      final improve = sections['improve'];
      final nextFocus = sections['nextFocus'];
      if (summary is! String ||
          wentWell is! String ||
          improve is! String ||
          nextFocus is! String) {
        throw const FormatException('Feedback cache sections are invalid.');
      }
      return LocalActivityFeedbackCacheEntry(
        cachedAt: cachedAt.toUtc(),
        sections: ActivityFeedbackSections(
          summary: summary,
          wentWell: wentWell,
          improve: improve,
          nextFocus: nextFocus,
        ),
      );
    } on TypeError {
      throw const FormatException('Feedback cache has invalid types.');
    }
  }
}

abstract interface class LocalActivityFeedbackCacheStore {
  Future<LocalActivityFeedbackCacheEntry?> load({
    required String ownerUid,
    required String runIdentity,
  });

  Future<void> save({
    required String ownerUid,
    required String runIdentity,
    required LocalActivityFeedbackCacheEntry entry,
  });

  Future<void> remove({required String ownerUid, required String runIdentity});
}

class SharedPreferencesLocalActivityFeedbackCacheStore
    implements LocalActivityFeedbackCacheStore {
  const SharedPreferencesLocalActivityFeedbackCacheStore({
    this.keyPrefix = 'runiac.activityFeedbackCache.v1.',
  });

  final String keyPrefix;

  @override
  Future<LocalActivityFeedbackCacheEntry?> load({
    required String ownerUid,
    required String runIdentity,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return LocalActivityFeedbackCacheEntry.tryDecode(
      preferences.getString(_key(ownerUid, runIdentity)),
    );
  }

  @override
  Future<void> save({
    required String ownerUid,
    required String runIdentity,
    required LocalActivityFeedbackCacheEntry entry,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final didPersist = await preferences.setString(
      _key(ownerUid, runIdentity),
      entry.encode(),
    );
    if (!didPersist) {
      throw StateError('Activity feedback cache write failed.');
    }
  }

  @override
  Future<void> remove({
    required String ownerUid,
    required String runIdentity,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key(ownerUid, runIdentity));
  }

  String _key(String ownerUid, String runIdentity) {
    return '$keyPrefix${_keyPart(ownerUid)}.${_keyPart(runIdentity)}';
  }

  String _keyPart(String value) {
    return base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  }
}
