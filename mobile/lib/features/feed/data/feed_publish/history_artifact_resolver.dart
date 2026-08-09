import 'dart:ui' as ui;

import '../../../../core/imaging/eight_bit_png.dart';
import '../../../run/domain/models/run_location_sample.dart';
import '../../../run/domain/models/run_summary_snapshot.dart';
import '../../../you/presentation/widgets/activity_route_preview.dart';
import '../../../you/presentation/widgets/activity_route_snapshot_thumbnail_cache.dart';
import '../../../you/presentation/widgets/activity_route_thumbnail_viewport.dart';
import 'feed_thumbnail_artifact.dart';
import 'feed_thumbnail_capture.dart';

/// Produces the thumbnail attached to a run when it is published to the feed.
///
/// A published post keeps its own image rather than re-rendering the run later:
/// the feed must look the same to everyone, including viewers who cannot read
/// the original run.
///
/// [CacheOnlyHistoryArtifactResolver] is the fast path — if the activity
/// history already rendered this route, reuse that image instead of paying for
/// a second render at publish time. Two generators exist because a run with a
/// usable route is shown as a route, and one without falls back to its metrics.
abstract interface class HistoryArtifactResolver {
  Future<FeedThumbnailArtifact?> resolve(ActivityRouteThumbnailRequest request);
}

class CacheOnlyHistoryArtifactResolver implements HistoryArtifactResolver {
  CacheOnlyHistoryArtifactResolver({
    ActivityRouteSnapshotThumbnailMemoryCache? cache,
    String? Function()? ownerUidProvider,
  }) : _provider = CachedActivityRouteThumbnailProvider(
         cache: cache ?? ActivityRouteSnapshotThumbnailMemoryCache(),
         ownerUidProvider: ownerUidProvider,
       );

  final ActivityRouteThumbnailProvider _provider;

  @override
  Future<FeedThumbnailArtifact?> resolve(
    ActivityRouteThumbnailRequest request,
  ) async {
    try {
      return await FeedThumbnailCapture(provider: _provider).capture(request);
    } on FeedThumbnailCaptureException {
      return null;
    }
  }
}

class MetricHistoryThumbnailGenerator {
  const MetricHistoryThumbnailGenerator();

  Future<FeedThumbnailArtifact> generate({
    required RunSummarySnapshot summary,
    required double devicePixelRatio,
  }) async {
    final scale = canonicalActivityRouteThumbnailScale(devicePixelRatio);
    final pixels = 88 * scale;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale.toDouble(), scale.toDouble());
    final background = ui.Paint()..color = const ui.Color(0xFF2F51C8);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(0, 0, 88, 88),
        const ui.Radius.circular(18),
      ),
      background,
    );
    final cardPaint = ui.Paint()..color = const ui.Color(0x22FFFFFF);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        const ui.Rect.fromLTWH(10, 10, 68, 26),
        const ui.Radius.circular(10),
      ),
      cardPaint,
    );
    final linePaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..strokeWidth = 2.2
      ..style = ui.PaintingStyle.stroke
      ..strokeCap = ui.StrokeCap.round
      ..strokeJoin = ui.StrokeJoin.round;
    final path = ui.Path()
      ..moveTo(18, 27)
      ..cubicTo(28, 14, 34, 34, 44, 22)
      ..cubicTo(52, 12, 59, 26, 70, 17);
    canvas.drawPath(path, linePaint);
    _drawText(
      canvas,
      '${summary.distanceKm} km',
      const ui.Offset(10, 45),
      fontSize: 18,
      fontWeight: ui.FontWeight.w800,
    );
    _drawText(
      canvas,
      'Distance',
      const ui.Offset(11, 65),
      fontSize: 7,
      color: const ui.Color(0xCCFFFFFF),
      fontWeight: ui.FontWeight.w700,
    );
    _drawText(
      canvas,
      summary.avgPace,
      const ui.Offset(48, 64),
      fontSize: 8,
      fontWeight: ui.FontWeight.w800,
    );
    final image = await recorder.endRecording().toImage(pixels, pixels);
    try {
      final data = await encodeEightBitPng(image);
      if (data == null) {
        throw const FeedThumbnailCaptureException(
          'This route preview cannot be posted. Please try again.',
        );
      }
      return FeedThumbnailArtifact(data);
    } finally {
      image.dispose();
    }
  }

  void _drawText(
    ui.Canvas canvas,
    String text,
    ui.Offset offset, {
    required double fontSize,
    ui.Color color = const ui.Color(0xFFFFFFFF),
    ui.FontWeight fontWeight = ui.FontWeight.w700,
  }) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: fontSize,
              fontWeight: fontWeight,
              maxLines: 1,
            ),
          )
          ..pushStyle(
            ui.TextStyle(
              color: color,
              fontSize: fontSize,
              fontWeight: fontWeight,
            ),
          )
          ..addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 76));
    canvas.drawParagraph(paragraph, offset);
  }
}

class RouteHistoryThumbnailGenerator {
  const RouteHistoryThumbnailGenerator({this.snapshotGenerator});

  final ActivityRouteSnapshotThumbnailGenerator? snapshotGenerator;

  Future<FeedThumbnailArtifact> generate({
    required ActivityRouteThumbnailRequest request,
  }) async {
    final generationRequest =
        ActivityRouteSnapshotThumbnailGenerationRequest.fromThumbnailRequest(
          request,
          styleId: 'summary-route-feed-preview-v1',
        );
    final generator = snapshotGenerator;
    if (generator != null && generationRequest != null) {
      final result = await generator.generate(generationRequest);
      final bytes = result.pngBytes;
      if (result.hasReadyImage && bytes != null) {
        return FeedThumbnailArtifact(bytes);
      }
    }
    final scale = request.canonicalDevicePixelRatio;
    final width = (request.logicalSize.width * scale).round();
    final height = (request.logicalSize.height * scale).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale.toDouble(), scale.toDouble());
    final logicalSize = request.logicalSize;
    _paintBackdrop(canvas, logicalSize);
    final viewport = ActivityRouteThumbnailViewport.fromRoute(
      request.route,
      logicalSize: logicalSize,
    );
    if (viewport.mode == ActivityRouteThumbnailViewportMode.meaningfulRoute) {
      final pathPaint = ui.Paint()
        ..color = const ui.Color(0xFFFB6414)
        ..strokeWidth = 4
        ..style = ui.PaintingStyle.stroke
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round;
      for (final segment in request.route.segments) {
        final path = _pathForSegment(segment, viewport);
        if (path != null) {
          canvas.drawPath(path, pathPaint);
        }
      }
    }
    final image = await recorder.endRecording().toImage(width, height);
    try {
      final data = await encodeEightBitPng(image);
      if (data == null) {
        throw const FeedThumbnailCaptureException(
          'This route preview cannot be posted. Please try again.',
        );
      }
      return FeedThumbnailArtifact(data);
    } finally {
      image.dispose();
    }
  }

  void _paintBackdrop(ui.Canvas canvas, ui.Size size) {
    canvas.drawRect(
      ui.Offset.zero & size,
      ui.Paint()..color = const ui.Color(0xFFF4F7FF),
    );
    final roadPaint = ui.Paint()
      ..color = const ui.Color(0xFFFFFFFF)
      ..strokeWidth = 6
      ..strokeCap = ui.StrokeCap.round;
    canvas.drawLine(
      ui.Offset(size.width * 0.06, size.height * 0.28),
      ui.Offset(size.width * 0.94, size.height * 0.14),
      roadPaint,
    );
    canvas.drawLine(
      ui.Offset(size.width * 0.12, size.height * 0.82),
      ui.Offset(size.width * 0.88, size.height * 0.38),
      roadPaint,
    );
    final waterPaint = ui.Paint()..color = const ui.Color(0x662AA8D8);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(
          size.width * 0.02,
          size.height * 0.08,
          size.width * 0.26,
          size.height * 0.42,
        ),
        const ui.Radius.circular(12),
      ),
      waterPaint,
    );
    final parkPaint = ui.Paint()..color = const ui.Color(0x6656B66D);
    canvas.drawRRect(
      ui.RRect.fromRectAndRadius(
        ui.Rect.fromLTWH(
          size.width * 0.68,
          size.height * 0.10,
          size.width * 0.24,
          size.height * 0.34,
        ),
        const ui.Radius.circular(10),
      ),
      parkPaint,
    );
    final gridPaint = ui.Paint()
      ..color = const ui.Color(0x667D93E1)
      ..strokeWidth = 1;
    for (var x = size.width * 0.18; x < size.width; x += size.width * 0.22) {
      canvas.drawLine(
        ui.Offset(x, 0),
        ui.Offset(x - 10, size.height),
        gridPaint,
      );
    }
    for (var y = size.height * 0.18; y < size.height; y += size.height * 0.18) {
      canvas.drawLine(ui.Offset(0, y), ui.Offset(size.width, y - 6), gridPaint);
    }
  }

  ui.Path? _pathForSegment(
    List<RunLocationSample> segment,
    ActivityRouteThumbnailViewport viewport,
  ) {
    final points = segment
        .where((point) => point.latitude.isFinite && point.longitude.isFinite)
        .toList(growable: false);
    if (points.length < 2) {
      return null;
    }
    final start = viewport.project(points.first);
    final path = ui.Path()..moveTo(start.dx, start.dy);
    for (final point in points.skip(1)) {
      final projected = viewport.project(point);
      path.lineTo(projected.dx, projected.dy);
    }
    return path;
  }
}
