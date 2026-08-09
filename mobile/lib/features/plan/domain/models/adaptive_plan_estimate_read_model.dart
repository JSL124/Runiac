enum AdaptivePlanEstimateConfidence { none, low, medium }

class AdaptivePlanEstimateReadModel {
  const AdaptivePlanEstimateReadModel({
    required this.averageRecentPaceSecondsPerKm,
    required this.completedRunCount,
    required this.positivePaceRunCount,
    required this.readinessBand,
    this.updatedAt,
    this.latestAcceptedActivityId,
    this.latestClientRunSessionId,
  });

  const AdaptivePlanEstimateReadModel.empty()
    : averageRecentPaceSecondsPerKm = null,
      completedRunCount = 0,
      positivePaceRunCount = 0,
      readinessBand = null,
      updatedAt = null,
      latestAcceptedActivityId = null,
      latestClientRunSessionId = null;

  factory AdaptivePlanEstimateReadModel.fromBackend(
    Map<String, Object?>? data,
  ) {
    if (data == null) {
      return const AdaptivePlanEstimateReadModel.empty();
    }

    return AdaptivePlanEstimateReadModel(
      averageRecentPaceSecondsPerKm: _readPositiveNumber(
        data['averageRecentPaceSecondsPerKm'],
      ),
      completedRunCount: _readNonNegativeInteger(data['completedRunCount']),
      positivePaceRunCount: _readNonNegativeInteger(
        data['positivePaceRunCount'],
      ),
      readinessBand: _readString(data['readinessBand']),
      updatedAt: _readString(data['updatedAt']),
      latestAcceptedActivityId: _readString(data['latestAcceptedActivityId']),
      latestClientRunSessionId: _readString(data['latestClientRunSessionId']),
    );
  }

  final num? averageRecentPaceSecondsPerKm;
  final int completedRunCount;
  final int positivePaceRunCount;
  final String? readinessBand;
  final String? updatedAt;
  final String? latestAcceptedActivityId;
  final String? latestClientRunSessionId;

  bool get isUsableForPlannedRun {
    return averageRecentPaceSecondsPerKm != null &&
        positivePaceRunCount > 0 &&
        readinessBand != 'conservative';
  }

  AdaptivePlanEstimateConfidence get estimateConfidence {
    if (!isUsableForPlannedRun) {
      return AdaptivePlanEstimateConfidence.none;
    }
    if (positivePaceRunCount >= 2 && readinessBand != 'building') {
      return AdaptivePlanEstimateConfidence.medium;
    }
    return AdaptivePlanEstimateConfidence.low;
  }

  int? targetDistanceMetersForDurationMinutes(int durationMinutes) {
    final pace = averageRecentPaceSecondsPerKm;
    if (!isUsableForPlannedRun || pace == null || durationMinutes <= 0) {
      return null;
    }
    return (durationMinutes * 60 / pace * 1000).round();
  }

  String? distanceLabelForDurationMinutes(int durationMinutes) {
    final meters = targetDistanceMetersForDurationMinutes(durationMinutes);
    if (meters == null) {
      return null;
    }
    return '~${(meters / 1000).toStringAsFixed(1)} km';
  }
}

int _readNonNegativeInteger(Object? value) {
  if (value is int && value >= 0) {
    return value;
  }
  return 0;
}

num? _readPositiveNumber(Object? value) {
  if (value is num && value.isFinite && value > 0) {
    return value;
  }
  return null;
}

String? _readString(Object? value) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  return null;
}
