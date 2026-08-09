part of 'current_session_activity_history.dart';

extension CurrentSessionActivityHistoryQueries
    on CurrentSessionActivityHistoryStore {
  List<RunActivityDisplayModel> recentRunsWithFallback(
    List<RunActivityDisplayModel> fallback, {
    int limit = 3,
  }) {
    final merged = <RunActivityDisplayModel>[
      for (final activity in _activities) activity.display,
      ...fallback,
    ];
    final seenIds = <String>{};
    final deduped = <RunActivityDisplayModel>[];

    for (final activity in merged) {
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
      deduped.add(activity);
      if (deduped.length == limit) {
        break;
      }
    }

    return deduped;
  }

  List<ActivityHistoryMonth> activityHistoryWithFallback(
    List<ActivityHistoryMonth> fallback,
  ) {
    if (_activities.isEmpty) {
      return fallback;
    }

    final sessionActivitiesByMonth = <String, List<RunActivityDisplayModel>>{};
    for (final activity in _activities) {
      final label = _monthLabelFor(activity.display.summary);
      sessionActivitiesByMonth
          .putIfAbsent(label, () => <RunActivityDisplayModel>[])
          .add(activity.display);
    }

    final merged = <ActivityHistoryMonth>[];
    final fallbackLabels = fallback.map((month) => month.label).toSet();

    for (final entry in sessionActivitiesByMonth.entries) {
      if (!fallbackLabels.contains(entry.key)) {
        merged.add(
          ActivityHistoryMonth(label: entry.key, activities: entry.value),
        );
      }
    }

    for (final month in fallback) {
      final sessionActivities = sessionActivitiesByMonth[month.label];
      if (sessionActivities == null) {
        merged.add(month);
        continue;
      }

      merged.add(
        ActivityHistoryMonth(
          label: month.label,
          activities: <RunActivityDisplayModel>[
            ...sessionActivities,
            ...month.activities,
          ],
        ),
      );
    }

    return merged;
  }

  String _monthLabelFor(RunSummarySnapshot summary) {
    final dateLabel = summary.dateLabel.trim();
    if (dateLabel.toLowerCase() == 'today') {
      return _formatMonth(_now());
    }

    final parsedDate = DateTime.tryParse(dateLabel);
    if (parsedDate != null) {
      return _formatMonth(parsedDate);
    }

    // Matches the D/M/YY format produced by RunSummaryScalarMapper._formatDate
    final dmyShort = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{2})$',
    ).firstMatch(dateLabel);
    if (dmyShort != null) {
      final month = int.tryParse(dmyShort.group(2)!);
      final shortYear = int.tryParse(dmyShort.group(3)!);
      if (month != null && shortYear != null) {
        return _formatMonth(DateTime(2000 + shortYear, month));
      }
    }

    final dayMonthYear = RegExp(
      r'^(\d{1,2})\s+([A-Za-z]+)\s+(\d{4})$',
    ).firstMatch(dateLabel);
    if (dayMonthYear != null) {
      final month = _monthNumber(dayMonthYear.group(2)!);
      final year = int.tryParse(dayMonthYear.group(3)!);
      if (month != null && year != null) {
        return _formatMonth(DateTime(year, month));
      }
    }

    final monthYear = RegExp(r'^([A-Za-z]+)\s+(\d{4})$').firstMatch(dateLabel);
    if (monthYear != null) {
      final month = _monthNumber(monthYear.group(1)!);
      final year = int.tryParse(monthYear.group(2)!);
      if (month != null && year != null) {
        return _formatMonth(DateTime(year, month));
      }
    }

    return _formatMonth(_now());
  }

  static String _formatMonth(DateTime date) {
    return '${_monthNames[date.month - 1]} ${date.year}';
  }

  static int? _monthNumber(String name) {
    final normalized = name.toLowerCase();
    for (var index = 0; index < _monthNames.length; index++) {
      if (_monthNames[index].toLowerCase().startsWith(normalized) ||
          normalized.startsWith(_monthNames[index].toLowerCase())) {
        return index + 1;
      }
    }
    return null;
  }
}

const _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
