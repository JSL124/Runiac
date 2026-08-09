enum RunSourceType {
  runiacGps,
  appleHealth,
  healthConnect,
  garminViaHealth,
  demoImport,
}

extension RunSourceTypeDisplay on RunSourceType {
  String get label {
    return switch (this) {
      RunSourceType.runiacGps => 'Runiac GPS',
      RunSourceType.appleHealth => 'Apple Health',
      RunSourceType.healthConnect => 'Health Connect',
      RunSourceType.garminViaHealth => 'Garmin via Health',
      RunSourceType.demoImport => 'Demo import',
    };
  }
}
