import '../models/run_location_permission_status.dart';

abstract interface class RunLocationPermissionService {
  Future<RunLocationPermissionStatus> checkStatus();

  Future<RunLocationPermissionStatus> requestPermission();
}
