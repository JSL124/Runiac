import 'completed_run_title_formatter.dart';
import 'run_calories_estimator.dart';

class RunSummaryScalarFields {
  const RunSummaryScalarFields({
    required this.title,
    required this.dateLabel,
    required this.timeLabel,
    required this.distanceKm,
    required this.avgPace,
    required this.duration,
    required this.calories,
    required this.routeName,
    required this.hasSufficientData,
  });

  final String title;
  final String dateLabel;
  final String timeLabel;
  final String distanceKm;
  final String avgPace;
  final String duration;
  final String calories;
  final String routeName;
  final bool hasSufficientData;
}

class RunSummaryScalarMapper {
  const RunSummaryScalarMapper({
    this.caloriesEstimator = const RunCaloriesEstimator(),
    this.titleFormatter = const CompletedRunTitleFormatter(),
  });

  final RunCaloriesEstimator caloriesEstimator;
  final CompletedRunTitleFormatter titleFormatter;

  RunSummaryScalarFields map({
    required DateTime completedAt,
    required int distanceMeters,
    required int durationSeconds,
    required int averagePaceSecondsPerKm,
    required String? routeLabel,
  }) {
    final calories = caloriesEstimator.estimate(
      bodyWeightKg: demoBodyWeightKgForCalories,
      movingSeconds: durationSeconds,
      distanceMeters: distanceMeters,
      averagePaceSecondsPerKm: averagePaceSecondsPerKm,
    );
    final avgPace = _formatPace(
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      paceSecondsPerKm: averagePaceSecondsPerKm,
    );
    return RunSummaryScalarFields(
      title: titleFormatter.format(completedAt: completedAt),
      dateLabel: _formatDate(completedAt),
      timeLabel: _formatTime(completedAt),
      distanceKm: _formatDistanceKm(distanceMeters),
      avgPace: avgPace,
      duration: _formatDuration(durationSeconds),
      calories: _formatCalories(calories),
      routeName: routeLabel ?? 'Private route',
      hasSufficientData: _hasSufficientSummaryData(
        distanceMeters: distanceMeters,
        durationSeconds: durationSeconds,
        avgPace: avgPace,
      ),
    );
  }

  String _formatDistanceKm(int distanceMeters) {
    return (distanceMeters / 1000).toStringAsFixed(2);
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatPace({
    required int distanceMeters,
    required int durationSeconds,
    required int paceSecondsPerKm,
  }) {
    if (distanceMeters < 50 ||
        durationSeconds < 60 ||
        paceSecondsPerKm <= 0 ||
        paceSecondsPerKm < 150 ||
        paceSecondsPerKm > 1800) {
      return '--';
    }

    final minutes = paceSecondsPerKm ~/ 60;
    final seconds = paceSecondsPerKm % 60;
    return '$minutes’${seconds.toString().padLeft(2, '0')}”';
  }

  bool _hasSufficientSummaryData({
    required int distanceMeters,
    required int durationSeconds,
    required String avgPace,
  }) {
    return distanceMeters >= 50 && durationSeconds >= 60 && avgPace != '--';
  }

  String _formatCalories(int? calories) {
    return calories == null ? '--' : calories.toString();
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    final year = local.year.toString().substring(2);
    return '${local.day}/${local.month}/$year';
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}
