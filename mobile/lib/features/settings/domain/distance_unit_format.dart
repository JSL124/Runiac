import 'models/app_settings.dart';

const double kilometersToMilesFactor = 0.621371;

double convertKilometers(double km, DistanceUnit unit) {
  return switch (unit) {
    DistanceUnit.kilometers => km,
    DistanceUnit.miles => km * kilometersToMilesFactor,
  };
}

String distanceUnitLabel(DistanceUnit unit) {
  return switch (unit) {
    DistanceUnit.kilometers => 'km',
    DistanceUnit.miles => 'mi',
  };
}

String paceUnitLabel(DistanceUnit unit) {
  return switch (unit) {
    DistanceUnit.kilometers => '/km',
    DistanceUnit.miles => '/mi',
  };
}
