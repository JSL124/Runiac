enum RunCadenceAvailabilityStatus { unknown, available, unavailable }

enum RunCadencePermissionStatus {
  notChecked,
  granted,
  denied,
  restricted,
  unknown,
  notRequired,
}

enum RunCadenceDiagnosticReason {
  none,
  available,
  unavailable,
  permissionGranted,
  permissionDenied,
  permissionRestricted,
  permissionUnknown,
  streamStarted,
  nativeError,
  nilData,
  filteredOutOfRange,
  malformedEvent,
  lifecycleError,
  acceptedSample,
}

class RunCadenceDiagnostics {
  const RunCadenceDiagnostics({
    this.availabilityStatus = RunCadenceAvailabilityStatus.unknown,
    this.permissionStatus = RunCadencePermissionStatus.notChecked,
    this.latestReason = RunCadenceDiagnosticReason.none,
    this.acceptedSampleCount = 0,
    this.filteredCadenceCount = 0,
    this.malformedEventCount = 0,
    this.nativeErrorCount = 0,
    this.lifecycleErrorCount = 0,
    this.latestFilteredCadenceSpm,
    this.latestNativeErrorCode,
    this.latestNativeErrorMessage,
    this.updatedAt,
  });

  const RunCadenceDiagnostics.initial()
    : availabilityStatus = RunCadenceAvailabilityStatus.unknown,
      permissionStatus = RunCadencePermissionStatus.notChecked,
      latestReason = RunCadenceDiagnosticReason.none,
      acceptedSampleCount = 0,
      filteredCadenceCount = 0,
      malformedEventCount = 0,
      nativeErrorCount = 0,
      lifecycleErrorCount = 0,
      latestFilteredCadenceSpm = null,
      latestNativeErrorCode = null,
      latestNativeErrorMessage = null,
      updatedAt = null;

  final RunCadenceAvailabilityStatus availabilityStatus;
  final RunCadencePermissionStatus permissionStatus;
  final RunCadenceDiagnosticReason latestReason;
  final int acceptedSampleCount;
  final int filteredCadenceCount;
  final int malformedEventCount;
  final int nativeErrorCount;
  final int lifecycleErrorCount;
  final int? latestFilteredCadenceSpm;
  final String? latestNativeErrorCode;
  final String? latestNativeErrorMessage;
  final DateTime? updatedAt;

  RunCadenceDiagnostics copyWith({
    RunCadenceAvailabilityStatus? availabilityStatus,
    RunCadencePermissionStatus? permissionStatus,
    RunCadenceDiagnosticReason? latestReason,
    int? acceptedSampleCount,
    int? filteredCadenceCount,
    int? malformedEventCount,
    int? nativeErrorCount,
    int? lifecycleErrorCount,
    int? latestFilteredCadenceSpm,
    String? latestNativeErrorCode,
    String? latestNativeErrorMessage,
    DateTime? updatedAt,
  }) {
    return RunCadenceDiagnostics(
      availabilityStatus: availabilityStatus ?? this.availabilityStatus,
      permissionStatus: permissionStatus ?? this.permissionStatus,
      latestReason: latestReason ?? this.latestReason,
      acceptedSampleCount: acceptedSampleCount ?? this.acceptedSampleCount,
      filteredCadenceCount: filteredCadenceCount ?? this.filteredCadenceCount,
      malformedEventCount: malformedEventCount ?? this.malformedEventCount,
      nativeErrorCount: nativeErrorCount ?? this.nativeErrorCount,
      lifecycleErrorCount: lifecycleErrorCount ?? this.lifecycleErrorCount,
      latestFilteredCadenceSpm:
          latestFilteredCadenceSpm ?? this.latestFilteredCadenceSpm,
      latestNativeErrorCode:
          latestNativeErrorCode ?? this.latestNativeErrorCode,
      latestNativeErrorMessage:
          latestNativeErrorMessage ?? this.latestNativeErrorMessage,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
