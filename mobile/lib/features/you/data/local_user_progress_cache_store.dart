import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/user_progress_read_model.dart';

class LocalUserProgressCacheEntry {
  const LocalUserProgressCacheEntry({
    required this.uid,
    required this.refreshedAt,
    required this.progress,
  });

  final String uid;
  final DateTime refreshedAt;
  final UserProgressReadModel progress;

  String encode() {
    return jsonEncode(<String, Object?>{
      'uid': uid,
      'refreshedAt': refreshedAt.toIso8601String(),
      'progress': <String, Object?>{
        'userId': progress.userId,
        'officialStreakLabel': progress.officialStreakLabel,
        'level': progress.level,
        'levelProgressFraction': progress.levelProgressFraction,
        'totalXp': progress.totalXp,
        'nextLevelXp': progress.nextLevelXp,
        'xpToNextLevel': progress.xpToNextLevel,
        'divisionKey': progress.divisionKey,
        'divisionLabel': progress.divisionLabel,
        'isMaxLevel': progress.isMaxLevel,
        'levelLabel': progress.levelLabel,
        'totalXpLabel': progress.totalXpLabel,
        'weeklyXpLabel': progress.weeklyXpLabel,
        'monthlyXpLabel': progress.monthlyXpLabel,
        'weeklyDistanceLabel': progress.weeklyDistanceLabel,
        'goalProgressLabel': progress.goalProgressLabel,
        'longestStreakLabel': progress.longestStreakLabel,
        'totalDistanceLabel': progress.totalDistanceLabel,
        'officialStreakCount': progress.officialStreakCount,
        'lastStreakRunDate': progress.lastStreakRunDate,
      },
    });
  }

  static LocalUserProgressCacheEntry? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) {
        throw const FormatException('User progress cache is not an object.');
      }
      final uid = decoded['uid'];
      final refreshedAt = DateTime.tryParse('${decoded['refreshedAt']}');
      final progress = decoded['progress'];
      if (uid is! String ||
          uid.isEmpty ||
          refreshedAt == null ||
          progress is! Map<String, Object?>) {
        throw const FormatException('User progress cache has invalid shape.');
      }
      return LocalUserProgressCacheEntry(
        uid: uid,
        refreshedAt: refreshedAt,
        progress: UserProgressReadModel(
          userId: _string(progress['userId']),
          officialStreakLabel: _string(progress['officialStreakLabel']),
          level: _nonNegativeInteger(progress['level']),
          levelProgressFraction: _progressFraction(
            progress['levelProgressFraction'],
          ),
          totalXp: _nonNegativeIntegerOrNull(progress['totalXp']),
          nextLevelXp: _nonNegativeIntegerOrNull(progress['nextLevelXp']),
          xpToNextLevel: _nonNegativeIntegerOrNull(progress['xpToNextLevel']),
          divisionKey: _string(progress['divisionKey']),
          divisionLabel: _string(progress['divisionLabel']),
          isMaxLevel: progress['isMaxLevel'] == true,
          levelLabel: _string(progress['levelLabel']),
          totalXpLabel: _string(progress['totalXpLabel']),
          weeklyXpLabel: _string(progress['weeklyXpLabel']),
          monthlyXpLabel: _string(progress['monthlyXpLabel']),
          weeklyDistanceLabel: _string(progress['weeklyDistanceLabel']),
          goalProgressLabel: _string(progress['goalProgressLabel']),
          longestStreakLabel: _string(progress['longestStreakLabel']),
          totalDistanceLabel: _string(progress['totalDistanceLabel']),
          officialStreakCount: _positiveInteger(
            progress['officialStreakCount'],
          ),
          lastStreakRunDate: _stringOrNull(progress['lastStreakRunDate']),
        ),
      );
    } on TypeError {
      throw const FormatException('User progress cache has invalid types.');
    }
  }

  static String _string(Object? value) {
    return value is String ? value : '';
  }

  static String? _stringOrNull(Object? value) {
    return value is String && value.isNotEmpty ? value : null;
  }

  static int? _positiveInteger(Object? value) {
    return value is int && value > 0 ? value : null;
  }

  static int _nonNegativeInteger(Object? value) {
    return value is int && value >= 0 ? value : 0;
  }

  static int? _nonNegativeIntegerOrNull(Object? value) {
    return value is int && value >= 0 ? value : null;
  }

  static double _progressFraction(Object? value) {
    if (value is int) {
      return value.clamp(0, 1).toDouble();
    }
    if (value is double) {
      return value.clamp(0, 1);
    }
    return 0;
  }
}

abstract interface class LocalUserProgressCacheStore {
  Future<LocalUserProgressCacheEntry?> load({required String uid});

  Future<void> save(LocalUserProgressCacheEntry entry);
}

class SharedPreferencesLocalUserProgressCacheStore
    implements LocalUserProgressCacheStore {
  const SharedPreferencesLocalUserProgressCacheStore({
    this.keyPrefix = 'runiac.userProgressCache.v1.',
  });

  final String keyPrefix;

  @override
  Future<LocalUserProgressCacheEntry?> load({required String uid}) async {
    final preferences = await SharedPreferences.getInstance();
    return LocalUserProgressCacheEntry.tryDecode(
      preferences.getString('$keyPrefix$uid'),
    );
  }

  @override
  Future<void> save(LocalUserProgressCacheEntry entry) async {
    final preferences = await SharedPreferences.getInstance();
    final didPersist = await preferences.setString(
      '$keyPrefix${entry.uid}',
      entry.encode(),
    );
    if (!didPersist) {
      throw StateError('User progress cache write failed.');
    }
  }
}
