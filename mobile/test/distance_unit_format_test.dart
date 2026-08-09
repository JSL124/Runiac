import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/settings/domain/distance_unit_format.dart';
import 'package:runiac_app/features/settings/domain/models/app_settings.dart';

void main() {
  group('convertKilometers', () {
    test('leaves the value unchanged for kilometers', () {
      expect(convertKilometers(10, DistanceUnit.kilometers), 10);
    });

    test('converts to miles using the kilometers-to-miles factor', () {
      final miles = convertKilometers(10, DistanceUnit.miles);

      expect(miles, closeTo(6.21371, 0.00001));
    });
  });

  group('distanceUnitLabel', () {
    test('labels kilometers as km', () {
      expect(distanceUnitLabel(DistanceUnit.kilometers), 'km');
    });

    test('labels miles as mi', () {
      expect(distanceUnitLabel(DistanceUnit.miles), 'mi');
    });
  });

  group('paceUnitLabel', () {
    test('labels kilometers pace as /km', () {
      expect(paceUnitLabel(DistanceUnit.kilometers), '/km');
    });

    test('labels miles pace as /mi', () {
      expect(paceUnitLabel(DistanceUnit.miles), '/mi');
    });
  });
}
