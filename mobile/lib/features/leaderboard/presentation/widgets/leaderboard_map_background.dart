import 'package:flutter/material.dart' hide Visibility;
import 'package:flutter/services.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;

import '../../../../core/theme/runiac_colors.dart';
import '../../../run/presentation/widgets/mapbox_runtime_config.dart';
import '../models/leaderboard_display_models.dart';

// The Singapore map behind the leaderboard, with the runner's planning area
// highlighted.
//
// Boundaries are drawn from a bundled GeoJSON asset rather than fetched, so the
// leaderboard renders without a network round trip and without a Mapbox tile
// request for the shapes themselves.
//
// The layer ids below are exported because the fill and line layers must be
// added, restyled and removed by name — Mapbox has no handle to hold onto, and
// adding a layer twice under the same id is an error on a real device.

const leaderboardPlanningAreaGeoJsonAsset =
    'assets/maps/master_plan_2025_planning_area_boundary_no_sea.geojson';

const leaderboardPlanningAreaSourceId =
    'leaderboard-singapore-planning-areas-2025';
const leaderboardPlanningAreaFillLayerId =
    'leaderboard-singapore-planning-area-fill';
const leaderboardPlanningAreaLineLayerId =
    'leaderboard-singapore-planning-area-line';
const leaderboardSelectedPlanningAreaFillLayerId =
    'leaderboard-selected-planning-area-fill';
const leaderboardSelectedPlanningAreaLineLayerId =
    'leaderboard-selected-planning-area-line';
const leaderboardPlanningAreaLabelLayerId =
    'leaderboard-singapore-planning-area-label';

class LeaderboardMapBackground extends StatelessWidget {
  const LeaderboardMapBackground({
    super.key,
    required this.regions,
    required this.selectedRegionId,
    required this.onRegionSelected,
  });

  final List<LeaderboardMapRegionDisplaySnapshot> regions;
  final String selectedRegionId;
  final ValueChanged<String> onRegionSelected;

  @override
  Widget build(BuildContext context) {
    final mapboxConfig = MapboxRuntimeConfig.fromEnvironment();
    return Stack(
      key: Key(
        mapboxConfig.hasPublicAccessToken
            ? 'leaderboard_mapbox_surface'
            : 'leaderboard_mapbox_fallback_surface',
      ),
      children: [
        Positioned.fill(
          child: mapboxConfig.hasPublicAccessToken
              ? _LeaderboardSingaporeMapboxBackground(
                  config: mapboxConfig,
                  regions: regions,
                  selectedRegionId: selectedRegionId,
                  onRegionSelected: onRegionSelected,
                )
              : const CustomPaint(painter: _LeaderboardMapPainter()),
        ),
        if (!mapboxConfig.hasPublicAccessToken)
          _FallbackPlanningAreaTouchTargets(
            regions: regions,
            selectedRegionId: selectedRegionId,
            onRegionSelected: onRegionSelected,
          ),
      ],
    );
  }
}

class _LeaderboardSingaporeMapboxBackground extends StatefulWidget {
  const _LeaderboardSingaporeMapboxBackground({
    required this.config,
    required this.regions,
    required this.selectedRegionId,
    required this.onRegionSelected,
  });

  final MapboxRuntimeConfig config;
  final List<LeaderboardMapRegionDisplaySnapshot> regions;
  final String selectedRegionId;
  final ValueChanged<String> onRegionSelected;

  @override
  State<_LeaderboardSingaporeMapboxBackground> createState() {
    return _LeaderboardSingaporeMapboxBackgroundState();
  }
}

class _LeaderboardSingaporeMapboxBackgroundState
    extends State<_LeaderboardSingaporeMapboxBackground> {
  static final mapbox.CameraViewportState _singaporeViewport =
      mapbox.CameraViewportState(
        center: mapbox.Point(coordinates: mapbox.Position(103.8198, 1.3521)),
        zoom: 10.25,
        pitch: 0,
        bearing: 0,
      );

  mapbox.MapboxMap? _mapboxMap;
  bool _styleReady = false;

  @override
  void initState() {
    super.initState();
    mapbox.MapboxOptions.setAccessToken(widget.config.accessToken);
  }

  @override
  void didUpdateWidget(
    covariant _LeaderboardSingaporeMapboxBackground oldWidget,
  ) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config.accessToken != widget.config.accessToken) {
      mapbox.MapboxOptions.setAccessToken(widget.config.accessToken);
    }
    if (oldWidget.selectedRegionId != widget.selectedRegionId ||
        oldWidget.regions != widget.regions) {
      _refreshSelectedPlanningAreaLayer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return mapbox.MapWidget(
      key: const Key('leaderboard_mapbox_widget'),
      styleUri: mapbox.MapboxStyles.MAPBOX_STREETS,
      viewport: _singaporeViewport,
      onMapCreated: _handleMapCreated,
      onStyleLoadedListener: _handleStyleLoaded,
    );
  }

  void _handleMapCreated(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    mapboxMap.addInteraction(
      mapbox.TapInteraction.onMap(_handleMapTap),
      interactionID: 'leaderboard-planning-area-map-tap',
    );
  }

  Future<void> _handleStyleLoaded(
    mapbox.StyleLoadedEventData styleLoadedEventData,
  ) async {
    _styleReady = true;
    await _installPlanningAreaLayers();
  }

  Future<void> _installPlanningAreaLayers() async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) {
      return;
    }

    final geoJson = await rootBundle.loadString(
      leaderboardPlanningAreaGeoJsonAsset,
    );
    await mapboxMap.style.addSource(
      mapbox.GeoJsonSource(
        id: leaderboardPlanningAreaSourceId,
        data: geoJson,
        tolerance: 0.18,
      ),
    );

    await mapboxMap.style.addLayer(
      mapbox.FillLayer(
        id: leaderboardPlanningAreaFillLayerId,
        sourceId: leaderboardPlanningAreaSourceId,
        filter: _supportedPlanningAreaFilterExpression(widget.regions),
        fillColorExpression: _planningAreaColorExpression(widget.regions),
        fillOpacity: 0.42,
        fillAntialias: true,
      ),
    );
    await mapboxMap.style.addLayer(
      mapbox.LineLayer(
        id: leaderboardPlanningAreaLineLayerId,
        sourceId: leaderboardPlanningAreaSourceId,
        filter: _supportedPlanningAreaFilterExpression(widget.regions),
        lineColor: RuniacColors.white.toARGB32(),
        lineOpacity: 0.72,
        lineWidth: 1.7,
      ),
    );
    await mapboxMap.style.addLayer(
      mapbox.FillLayer(
        id: leaderboardSelectedPlanningAreaFillLayerId,
        sourceId: leaderboardPlanningAreaSourceId,
        filter: _selectedPlanningAreaFilterExpression,
        fillColor: RuniacColors.accentOrange.toARGB32(),
        fillOpacity: 0.66,
        fillAntialias: true,
      ),
    );
    await mapboxMap.style.addLayer(
      mapbox.LineLayer(
        id: leaderboardSelectedPlanningAreaLineLayerId,
        sourceId: leaderboardPlanningAreaSourceId,
        filter: _selectedPlanningAreaFilterExpression,
        lineColor: RuniacColors.accentOrange.toARGB32(),
        lineOpacity: 0.96,
        lineWidth: 4.2,
      ),
    );
    await mapboxMap.style.addLayer(
      mapbox.SymbolLayer(
        id: leaderboardPlanningAreaLabelLayerId,
        sourceId: leaderboardPlanningAreaSourceId,
        filter: _supportedPlanningAreaFilterExpression(widget.regions),
        textFieldExpression: const ['get', 'PLN_AREA_N'],
        textSize: 10.5,
        textMaxWidth: 6,
        textColor: const Color(0xFF172033).toARGB32(),
        textHaloColor: RuniacColors.white.toARGB32(),
        textHaloWidth: 1.7,
        textAllowOverlap: false,
        textIgnorePlacement: false,
        textOptional: true,
        symbolSortKey: 3,
      ),
    );
  }

  Future<void> _refreshSelectedPlanningAreaLayer() async {
    if (!_styleReady) {
      return;
    }

    final mapboxMap = _mapboxMap;
    final selectedRegion = _selectedRegion;
    if (mapboxMap == null || selectedRegion == null) {
      return;
    }

    await mapboxMap.style.updateLayer(
      mapbox.FillLayer(
        id: leaderboardSelectedPlanningAreaFillLayerId,
        sourceId: leaderboardPlanningAreaSourceId,
        filter: _selectedPlanningAreaFilterExpression,
        fillColor: selectedRegion.color.toARGB32(),
        fillOpacity: selectedRegion.isUserRegion ? 0.66 : 0.52,
        fillAntialias: true,
      ),
    );
    await mapboxMap.style.updateLayer(
      mapbox.LineLayer(
        id: leaderboardSelectedPlanningAreaLineLayerId,
        sourceId: leaderboardPlanningAreaSourceId,
        filter: _selectedPlanningAreaFilterExpression,
        lineColor: selectedRegion.color.toARGB32(),
        lineOpacity: 0.96,
        lineWidth: selectedRegion.isUserRegion ? 4.2 : 3.0,
      ),
    );
  }

  Future<void> _handleMapTap(mapbox.MapContentGestureContext context) async {
    final mapboxMap = _mapboxMap;
    if (mapboxMap == null) {
      return;
    }

    final features = await mapboxMap.queryRenderedFeatures(
      mapbox.RenderedQueryGeometry.fromScreenCoordinate(context.touchPosition),
      mapbox.RenderedQueryOptions(
        layerIds: [leaderboardPlanningAreaFillLayerId],
      ),
    );
    for (final queriedFeature in features) {
      final planningAreaName = _planningAreaNameFromFeature(
        queriedFeature?.queriedFeature.feature,
      );
      final matchingRegion = _regionForPlanningAreaName(planningAreaName);
      if (matchingRegion != null) {
        widget.onRegionSelected(matchingRegion.regionId);
        return;
      }
    }
  }

  LeaderboardMapRegionDisplaySnapshot? get _selectedRegion {
    for (final region in widget.regions) {
      if (region.regionId == widget.selectedRegionId) {
        return region;
      }
    }

    return null;
  }

  List<Object> get _selectedPlanningAreaFilterExpression {
    final selectedRegion = _selectedRegion;
    return [
      '==',
      ['get', 'PLN_AREA_N'],
      selectedRegion?.planningAreaName ?? '',
    ];
  }

  LeaderboardMapRegionDisplaySnapshot? _regionForPlanningAreaName(
    String? planningAreaName,
  ) {
    if (planningAreaName == null) {
      return null;
    }

    for (final region in widget.regions) {
      if (region.planningAreaName == planningAreaName) {
        return region;
      }
    }

    return null;
  }
}

class _FallbackPlanningAreaTouchTargets extends StatelessWidget {
  const _FallbackPlanningAreaTouchTargets({
    required this.regions,
    required this.selectedRegionId,
    required this.onRegionSelected,
  });

  final List<LeaderboardMapRegionDisplaySnapshot> regions;
  final String selectedRegionId;
  final ValueChanged<String> onRegionSelected;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (final region in regions)
          Align(
            alignment: region.fallbackAlignment,
            child: _FallbackPlanningAreaButton(
              region: region,
              selected: region.regionId == selectedRegionId,
              onTap: () => onRegionSelected(region.regionId),
            ),
          ),
      ],
    );
  }
}

class _FallbackPlanningAreaButton extends StatelessWidget {
  const _FallbackPlanningAreaButton({
    required this.region,
    required this.selected,
    required this.onTap,
  });

  final LeaderboardMapRegionDisplaySnapshot region;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final highlighted = selected || region.isUserRegion;
    return Semantics(
      button: true,
      label: region.semanticLabel,
      child: GestureDetector(
        key: Key('leaderboard_planning_area_touch_${region.regionId}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: region.isUserRegion
                  ? const Key('leaderboard_user_planning_area_highlight')
                  : null,
              width: highlighted ? 34 : 24,
              height: highlighted ? 34 : 24,
              decoration: BoxDecoration(
                color: region.color.withValues(
                  alpha: highlighted ? 0.74 : 0.48,
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: highlighted ? Colors.white : region.color,
                  width: highlighted ? 3 : 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x24172033),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
            ),
            if (region.isUserRegion) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xF7FFFFFF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFFFD1BC)),
                ),
                child: const Text(
                  'Your ranked area',
                  style: TextStyle(
                    color: RuniacColors.accentOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LeaderboardMapPainter extends CustomPainter {
  const _LeaderboardMapPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE9E3D8),
    );

    _drawLandBlocks(canvas, size);
    _drawRoads(canvas, size);
    _drawRegionBoundaries(canvas, size);
    _drawRoute(canvas, size);
  }

  void _drawLandBlocks(Canvas canvas, Size size) {
    final lightBlockPaint = Paint()..color = const Color(0xFFF2EEE5);
    final greenBlockPaint = Paint()..color = const Color(0xFFDDE7D8);
    final warmBlockPaint = Paint()..color = const Color(0xFFEFE0D3);

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-30, 96, size.width * 0.52, size.height * 0.26),
          const Radius.circular(28),
        ),
        greenBlockPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.54,
            128,
            size.width * 0.58,
            size.height * 0.28,
          ),
          const Radius.circular(30),
        ),
        lightBlockPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(18, size.height * 0.47, size.width * 0.48, 148),
          const Radius.circular(26),
        ),
        warmBlockPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.53,
            size.height * 0.58,
            size.width * 0.44,
            154,
          ),
          const Radius.circular(26),
        ),
        greenBlockPaint,
      );
  }

  void _drawRoads(Canvas canvas, Size size) {
    final mainRoadPaint = Paint()
      ..color = const Color(0xEFFFFFFF)
      ..strokeWidth = 24
      ..strokeCap = StrokeCap.round;
    final softRoadPaint = Paint()
      ..color = const Color(0xBFFFFFFF)
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas
      ..drawLine(
        Offset(-size.width * 0.12, 164),
        Offset(size.width * 1.08, size.height * 0.44),
        mainRoadPaint,
      )
      ..drawLine(
        Offset(size.width * 0.72, -30),
        Offset(size.width * 0.32, size.height * 0.98),
        mainRoadPaint,
      )
      ..drawLine(
        Offset(-28, size.height * 0.62),
        Offset(size.width * 0.86, size.height * 0.55),
        softRoadPaint,
      )
      ..drawLine(
        Offset(size.width * 0.12, size.height * 0.30),
        Offset(size.width * 0.92, size.height * 0.82),
        softRoadPaint,
      );
  }

  void _drawRegionBoundaries(Canvas canvas, Size size) {
    final boundaryPaint = Paint()
      ..color = RuniacColors.white.withValues(alpha: 0.38)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(18, 150, size.width * 0.36, size.height * 0.24),
          const Radius.circular(32),
        ),
        boundaryPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.56,
            210,
            size.width * 0.34,
            size.height * 0.25,
          ),
          const Radius.circular(34),
        ),
        boundaryPaint,
      )
      ..drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(54, size.height * 0.58, size.width * 0.45, 156),
          const Radius.circular(30),
        ),
        boundaryPaint,
      );
  }

  void _drawRoute(Canvas canvas, Size size) {
    final routePaint = Paint()
      ..color = RuniacColors.primaryBlue.withValues(alpha: 0.74)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final routePath = Path()
      ..moveTo(size.width * 0.16, size.height * 0.34)
      ..cubicTo(
        size.width * 0.34,
        size.height * 0.24,
        size.width * 0.47,
        size.height * 0.44,
        size.width * 0.64,
        size.height * 0.34,
      )
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.27,
        size.width * 0.86,
        size.height * 0.44,
        size.width * 0.72,
        size.height * 0.52,
      );

    canvas.drawPath(routePath, routePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

List<Object> _supportedPlanningAreaFilterExpression(
  List<LeaderboardMapRegionDisplaySnapshot> regions,
) {
  return [
    'in',
    ['get', 'PLN_AREA_N'],
    ['literal', _uniquePlanningAreaNames(regions)],
  ];
}

List<Object> _planningAreaColorExpression(
  List<LeaderboardMapRegionDisplaySnapshot> regions,
) {
  return [
    'match',
    ['get', 'PLN_AREA_N'],
    for (final region in regions) ...[
      region.planningAreaName,
      _toMapboxColor(region.color),
    ],
    _toMapboxColor(RuniacColors.primaryBlue),
  ];
}

List<String> _uniquePlanningAreaNames(
  List<LeaderboardMapRegionDisplaySnapshot> regions,
) {
  final names = <String>{};
  for (final region in regions) {
    names.add(region.planningAreaName);
  }

  return names.toList(growable: false);
}

String _toMapboxColor(Color color) {
  return '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
}

String? _planningAreaNameFromFeature(Map<String?, Object?>? feature) {
  final properties = feature?['properties'];
  if (properties is Map) {
    final planningAreaName = properties['PLN_AREA_N'];
    if (planningAreaName is String) {
      return planningAreaName;
    }
  }

  final planningAreaName = feature?['PLN_AREA_N'];
  if (planningAreaName is String) {
    return planningAreaName;
  }

  return null;
}
