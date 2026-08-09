import '../models/run_location_sample.dart';

abstract interface class RunLocationPreviewProvider {
  Future<RunLocationSample> currentLocation();
}
