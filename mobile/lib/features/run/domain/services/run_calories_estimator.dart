// TODO: Replace this demo-only value with onboarding/profile body weight.
const demoBodyWeightKgForCalories = 95.0;

class RunCaloriesEstimator {
  const RunCaloriesEstimator();

  int? estimate({
    required double? bodyWeightKg,
    required int movingSeconds,
    required int distanceMeters,
    required int averagePaceSecondsPerKm,
  }) {
    if (bodyWeightKg == null || !bodyWeightKg.isFinite || bodyWeightKg <= 0) {
      return null;
    }
    if (movingSeconds <= 0 ||
        distanceMeters <= 0 ||
        averagePaceSecondsPerKm <= 0) {
      return null;
    }

    final speedKmh = distanceMeters / movingSeconds * 3.6;
    final bucketSpeedKmh = (speedKmh * 10).round() / 10;
    final met = _metForSpeedKmh(bucketSpeedKmh);
    if (met == null) {
      return null;
    }

    final movingMinutes = movingSeconds / 60;
    final calories = met * 3.5 * bodyWeightKg / 200 * movingMinutes;
    return calories.round();
  }

  double? _metForSpeedKmh(double speedKmh) {
    if (speedKmh >= 4.0 && speedKmh <= 6.3) {
      return 4.3;
    }
    if (speedKmh >= 6.4 && speedKmh <= 7.7) {
      return 6.5;
    }
    if (speedKmh >= 7.8 && speedKmh <= 9.6) {
      return 8.8;
    }
    if (speedKmh >= 9.7 && speedKmh <= 11.2) {
      return 9.8;
    }
    if (speedKmh > 11.2) {
      return 10.5;
    }
    return null;
  }
}
