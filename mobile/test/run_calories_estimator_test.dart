import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/services/run_calories_estimator.dart';

void main() {
  group('RunCaloriesEstimator', () {
    const estimator = RunCaloriesEstimator();

    test('estimates whole-number calories for valid beginner run metrics', () {
      final calories = estimator.estimate(
        bodyWeightKg: demoBodyWeightKgForCalories,
        movingSeconds: 1500,
        distanceMeters: 3200,
        averagePaceSecondsPerKm: 469,
      );

      expect(calories, 270);
    });

    test('uses MET buckets and caps faster valid running speeds', () {
      expect(
        estimator.estimate(
          bodyWeightKg: demoBodyWeightKgForCalories,
          movingSeconds: 900,
          distanceMeters: 1200,
          averagePaceSecondsPerKm: 750,
        ),
        107,
      );
      expect(
        estimator.estimate(
          bodyWeightKg: demoBodyWeightKgForCalories,
          movingSeconds: 900,
          distanceMeters: 1800,
          averagePaceSecondsPerKm: 500,
        ),
        162,
      );
      expect(
        estimator.estimate(
          bodyWeightKg: demoBodyWeightKgForCalories,
          movingSeconds: 900,
          distanceMeters: 2400,
          averagePaceSecondsPerKm: 375,
        ),
        219,
      );
      expect(
        estimator.estimate(
          bodyWeightKg: demoBodyWeightKgForCalories,
          movingSeconds: 900,
          distanceMeters: 2800,
          averagePaceSecondsPerKm: 321,
        ),
        244,
      );
      expect(
        estimator.estimate(
          bodyWeightKg: demoBodyWeightKgForCalories,
          movingSeconds: 900,
          distanceMeters: 3600,
          averagePaceSecondsPerKm: 250,
        ),
        262,
      );
    });

    test(
      'returns unavailable for walking, missing, zero, or invalid metrics',
      () {
        expect(
          estimator.estimate(
            bodyWeightKg: demoBodyWeightKgForCalories,
            movingSeconds: 900,
            distanceMeters: 900,
            averagePaceSecondsPerKm: 1000,
          ),
          isNull,
        );
        expect(
          estimator.estimate(
            bodyWeightKg: null,
            movingSeconds: 1500,
            distanceMeters: 3200,
            averagePaceSecondsPerKm: 469,
          ),
          isNull,
        );
        expect(
          estimator.estimate(
            bodyWeightKg: 0,
            movingSeconds: 1500,
            distanceMeters: 3200,
            averagePaceSecondsPerKm: 469,
          ),
          isNull,
        );
        expect(
          estimator.estimate(
            bodyWeightKg: demoBodyWeightKgForCalories,
            movingSeconds: 0,
            distanceMeters: 3200,
            averagePaceSecondsPerKm: 469,
          ),
          isNull,
        );
        expect(
          estimator.estimate(
            bodyWeightKg: demoBodyWeightKgForCalories,
            movingSeconds: 1500,
            distanceMeters: 0,
            averagePaceSecondsPerKm: 469,
          ),
          isNull,
        );
        expect(
          estimator.estimate(
            bodyWeightKg: demoBodyWeightKgForCalories,
            movingSeconds: 1500,
            distanceMeters: 3200,
            averagePaceSecondsPerKm: 0,
          ),
          isNull,
        );
      },
    );
  });
}
