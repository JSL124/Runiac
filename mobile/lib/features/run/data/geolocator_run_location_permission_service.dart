import 'package:geolocator/geolocator.dart' as geolocator;

import '../domain/models/run_location_permission_status.dart';
import '../domain/repositories/run_location_permission_service.dart';

class GeolocatorRunLocationPermissionService
    implements RunLocationPermissionService {
  const GeolocatorRunLocationPermissionService();

  @override
  Future<RunLocationPermissionStatus> checkStatus() async {
    return _statusFromPermission(requestIfDenied: false);
  }

  @override
  Future<RunLocationPermissionStatus> requestPermission() async {
    return _statusFromPermission(requestIfDenied: true);
  }

  Future<RunLocationPermissionStatus> _statusFromPermission({
    required bool requestIfDenied,
  }) async {
    try {
      final serviceEnabled =
          await geolocator.Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return RunLocationPermissionStatus.serviceDisabled;
      }

      var permission = await geolocator.Geolocator.checkPermission();
      if (permission == geolocator.LocationPermission.denied &&
          requestIfDenied) {
        permission = await geolocator.Geolocator.requestPermission();
      }

      return switch (permission) {
        geolocator.LocationPermission.always ||
        geolocator.LocationPermission.whileInUse =>
          RunLocationPermissionStatus.granted,
        geolocator.LocationPermission.denied =>
          RunLocationPermissionStatus.denied,
        geolocator.LocationPermission.deniedForever =>
          RunLocationPermissionStatus.deniedForever,
        geolocator.LocationPermission.unableToDetermine =>
          RunLocationPermissionStatus.unavailable,
      };
    } catch (_) {
      return RunLocationPermissionStatus.unavailable;
    }
  }
}
