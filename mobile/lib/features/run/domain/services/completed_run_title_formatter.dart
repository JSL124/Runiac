class CompletedRunTitleFormatter {
  const CompletedRunTitleFormatter();

  String format({required DateTime completedAt}) {
    final localCompletedAt = completedAt.toLocal();
    final weekday = _weekdayLabel(localCompletedAt.weekday);
    final daypart = _daypartLabel(localCompletedAt.hour);
    return '$weekday $daypart Run';
  }

  String _weekdayLabel(int weekday) {
    return switch (weekday) {
      DateTime.monday => 'Monday',
      DateTime.tuesday => 'Tuesday',
      DateTime.wednesday => 'Wednesday',
      DateTime.thursday => 'Thursday',
      DateTime.friday => 'Friday',
      DateTime.saturday => 'Saturday',
      DateTime.sunday => 'Sunday',
      _ => throw ArgumentError.value(weekday, 'weekday'),
    };
  }

  String _daypartLabel(int hour) {
    if (hour >= 5 && hour < 12) {
      return 'Morning';
    }
    if (hour >= 12 && hour < 17) {
      return 'Afternoon';
    }
    if (hour >= 17 && hour < 21) {
      return 'Evening';
    }
    return 'Night';
  }
}
