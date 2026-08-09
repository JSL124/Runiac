enum RunLocationPermissionStatus {
  checking,
  granted,
  denied,
  deniedForever,
  notificationDenied,
  serviceDisabled,
  unavailable,
}

extension RunLocationPermissionStatusCopy on RunLocationPermissionStatus {
  String get message {
    return switch (this) {
      RunLocationPermissionStatus.checking =>
        'Checking GPS permission for your run.',
      RunLocationPermissionStatus.granted => 'GPS is ready for your run.',
      RunLocationPermissionStatus.denied =>
        'Location helps measure your distance and pace. You can try again when you are ready.',
      RunLocationPermissionStatus.deniedForever =>
        'Location is blocked for Runiac. Open app settings to allow location for runs.',
      RunLocationPermissionStatus.notificationDenied =>
        'Notifications are needed to keep tracking visible while Runiac is in the background.',
      RunLocationPermissionStatus.serviceDisabled =>
        'Turn on location services to track distance and pace during your run.',
      RunLocationPermissionStatus.unavailable =>
        'GPS is not available right now. You can still use the demo run mode.',
    };
  }

  bool get canStartRun => this == RunLocationPermissionStatus.granted;
}
