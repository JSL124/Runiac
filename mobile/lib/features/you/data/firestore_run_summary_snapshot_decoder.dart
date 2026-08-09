import '../../run/domain/models/elevation_analysis_series.dart';
import '../../run/domain/models/pace_analysis_series.dart';
import '../../run/domain/models/run_location_sample.dart';
import '../../run/domain/models/run_route_snapshot.dart';

/// Reconstructs the heavy parts of a past run — route, pace series, elevation —
/// from its stored Firestore document.
///
/// Kept apart from the repository because this is the untrusted boundary: the
/// document may have been written by an older app version or be partially
/// missing. Decoding therefore validates rather than casts, and reports what it
/// could not rebuild (see [FirestoreRunSummaryDetails.hasValidPersistedRoutePreview])
/// so the summary can show a run without a route instead of failing to open it.
class FirestoreRunSummaryDetails {
  const FirestoreRunSummaryDetails({
    required this.route,
    required this.paceAnalysisSeries,
    required this.elevationSeries,
    required this.hasValidPersistedRoutePreview,
  });

  static const empty = FirestoreRunSummaryDetails(
    route: RunRouteSnapshot.empty,
    paceAnalysisSeries: null,
    elevationSeries: ElevationAnalysisSeries.unavailable(),
    hasValidPersistedRoutePreview: false,
  );

  final RunRouteSnapshot route;
  final PaceAnalysisSeries? paceAnalysisSeries;
  final ElevationAnalysisSeries elevationSeries;
  final bool hasValidPersistedRoutePreview;
}

class FirestoreRunSummarySnapshotDecoder {
  const FirestoreRunSummarySnapshotDecoder();

  FirestoreRunSummaryDetails decode(Map<String, Object?> source) {
    final route = _readRoutePreview(source['routePreview']);
    return FirestoreRunSummaryDetails(
      route: route ?? RunRouteSnapshot.empty,
      paceAnalysisSeries: _readPaceAnalysisSeries(source['paceAnalysisSeries']),
      elevationSeries:
          _readElevationAnalysisSeries(source['elevationSeries']) ??
          const ElevationAnalysisSeries.unavailable(),
      hasValidPersistedRoutePreview: route != null,
    );
  }

  RunRouteSnapshot? _readRoutePreview(Object? raw) {
    final source = _readMap(raw);
    final rawSegments = _readList(source?['segments']);
    if (source == null ||
        !_hasExactKeys(source, const <String>{'segments'}) ||
        rawSegments == null ||
        rawSegments.isEmpty ||
        rawSegments.length > _maximumRouteSegmentCount) {
      return null;
    }

    var pointCount = 0;
    final segments = <List<RunLocationSample>>[];
    for (final rawSegment in rawSegments) {
      final segment = _readMap(rawSegment);
      final rawPoints = _readList(segment?['points']);
      if (segment == null ||
          !_hasExactKeys(segment, const <String>{'points'}) ||
          rawPoints == null ||
          rawPoints.isEmpty) {
        return null;
      }
      final points = <RunLocationSample>[];
      for (final rawPoint in rawPoints) {
        final point = _readRoutePreviewPoint(rawPoint, pointCount);
        if (point == null || ++pointCount > _maximumRoutePointCount) {
          return null;
        }
        points.add(point);
      }
      segments.add(List<RunLocationSample>.unmodifiable(points));
    }
    if (pointCount == 0) {
      return null;
    }

    return RunRouteSnapshot(
      segments: List<List<RunLocationSample>>.unmodifiable(segments),
      lastKnownLocation: segments.last.last,
    );
  }

  RunLocationSample? _readRoutePreviewPoint(Object? raw, int pointIndex) {
    final source = _readMap(raw);
    if (source == null ||
        !_hasExactKeys(source, const <String>{'latitude', 'longitude'})) {
      return null;
    }
    final latitude = _readFiniteDouble(source['latitude']);
    final longitude = _readFiniteDouble(source['longitude']);
    if (latitude == null ||
        !_hasThreeDecimalPrecision(latitude) ||
        latitude < -90 ||
        latitude > 90 ||
        longitude == null ||
        !_hasThreeDecimalPrecision(longitude) ||
        longitude < -180 ||
        longitude > 180) {
      return null;
    }
    return RunLocationSample(
      // Persisted previews intentionally contain no real timestamps. This
      // deterministic sequence exists only for the local painter/map camera.
      recordedAt: DateTime.fromMillisecondsSinceEpoch(
        pointIndex * Duration.millisecondsPerSecond,
        isUtc: true,
      ),
      latitude: latitude,
      longitude: longitude,
    );
  }

  PaceAnalysisSeries? _readPaceAnalysisSeries(Object? raw) {
    final source = _readMap(raw);
    final rawSamples = _readList(source?['samples']);
    if (source == null ||
        source['source'] != PaceAnalysisSource.localAccepted.name ||
        source['confidence'] != PaceAnalysisConfidence.derived.name ||
        rawSamples == null ||
        rawSamples.isEmpty ||
        rawSamples.length > _maximumAnalysisSampleCount) {
      return null;
    }
    final samples = <PaceAnalysisSample>[];
    for (final rawSample in rawSamples) {
      final sample = _readPaceAnalysisSample(rawSample);
      if (sample == null) {
        return null;
      }
      samples.add(sample);
    }
    return PaceAnalysisSeries.localAccepted(samples: samples);
  }

  PaceAnalysisSample? _readPaceAnalysisSample(Object? raw) {
    final source = _readMap(raw);
    if (source == null ||
        source['status'] != PaceAnalysisSampleStatus.accepted.name) {
      return null;
    }
    final elapsedSeconds = _readExactInt(source['elapsedSeconds']);
    final cumulativeDistanceMeters = _readFiniteDouble(
      source['cumulativeDistanceMeters'],
    );
    final paceSecondsPerKm = _readExactInt(source['paceSecondsPerKm']);
    if (elapsedSeconds == null ||
        elapsedSeconds < 0 ||
        cumulativeDistanceMeters == null ||
        cumulativeDistanceMeters < 0 ||
        paceSecondsPerKm == null ||
        paceSecondsPerKm < minPaceAnalysisPaceSecondsPerKm ||
        paceSecondsPerKm > maxPaceAnalysisPaceSecondsPerKm) {
      return null;
    }
    return PaceAnalysisSample.accepted(
      elapsedSeconds: elapsedSeconds,
      cumulativeDistanceMeters: cumulativeDistanceMeters,
      paceSecondsPerKm: paceSecondsPerKm,
    );
  }

  ElevationAnalysisSeries? _readElevationAnalysisSeries(Object? raw) {
    final source = _readMap(raw);
    final rawSamples = _readList(source?['samples']);
    if (source == null ||
        source['source'] != ElevationAnalysisSource.runiacLocalAccepted.name ||
        source['confidence'] != ElevationAnalysisConfidence.medium.name ||
        rawSamples == null ||
        rawSamples.isEmpty ||
        rawSamples.length > _maximumAnalysisSampleCount) {
      return null;
    }
    final samples = <ElevationAnalysisSample>[];
    for (final rawSample in rawSamples) {
      final source = _readMap(rawSample);
      final distanceKm = _readFiniteDouble(source?['distanceKm']);
      final elevationMeters = _readFiniteDouble(source?['elevationMeters']);
      if (source == null ||
          distanceKm == null ||
          distanceKm < 0 ||
          elevationMeters == null) {
        return null;
      }
      samples.add(
        ElevationAnalysisSample(
          distanceKm: distanceKm,
          elevationMeters: elevationMeters,
        ),
      );
    }
    return ElevationAnalysisSeries.localAccepted(samples: samples);
  }

  Map<String, Object?>? _readMap(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return null;
  }

  List<Object?>? _readList(Object? value) {
    return value is List ? List<Object?>.from(value) : null;
  }

  double? _readFiniteDouble(Object? value) {
    return value is num && value.isFinite ? value.toDouble() : null;
  }

  bool _hasExactKeys(Map<String, Object?> source, Set<String> expected) {
    return source.length == expected.length &&
        source.keys.every(expected.contains);
  }

  bool _hasThreeDecimalPrecision(double value) {
    return double.parse(value.toStringAsFixed(3)) == value;
  }

  int? _readExactInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    return null;
  }
}

const _maximumRouteSegmentCount = 64;
const _maximumRoutePointCount = 256;
const _maximumAnalysisSampleCount = 360;
