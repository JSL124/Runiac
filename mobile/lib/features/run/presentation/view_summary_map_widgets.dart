part of 'view_summary_screen.dart';

/// The route preview on the run summary, and the full-screen map it expands to.
///
/// [_MapPreview] picks between the interactive Mapbox surface and
/// [_StaticMapPreview] depending on whether a token is configured, so callers
/// never have to branch on it. [_SourceLabel] states where the run's data came
/// from — a Runiac GPS run and an imported workout must not look identical.
class _SourceLabel extends StatelessWidget {
  const _SourceLabel({required this.sourceLabel});

  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Text(
        sourceLabel,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _rBlue60,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1.15,
        ),
      ),
    );
  }
}

class _MapPreview extends StatelessWidget {
  const _MapPreview({
    required this.routeName,
    required this.route,
    this.mapboxAccessToken,
    this.mapboxBuilder,
  });

  final String routeName;
  final RunRouteSnapshot route;
  final String? mapboxAccessToken;
  final CompletedRouteMapboxBuilder? mapboxBuilder;

  @override
  Widget build(BuildContext context) {
    final canOpenExpanded = route.hasRoute || route.hasLocation;
    final preview = _MapPreviewFrame(
      child: CompletedRouteMapSurface(
        route: route,
        mapboxAccessToken: mapboxAccessToken,
        mapboxBuilder: mapboxBuilder,
        fallback: _StaticMapPreview(route: route),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Stack(
        children: [
          preview,
          if (canOpenExpanded)
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const Key('summary_route_preview_tap_target'),
                  borderRadius: BorderRadius.circular(_cardRadius),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        fullscreenDialog: true,
                        builder: (context) => _ExpandedRouteMapScreen(
                          routeName: routeName,
                          route: route,
                          mapboxAccessToken: mapboxAccessToken,
                          mapboxBuilder: mapboxBuilder,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapPreviewFrame extends StatelessWidget {
  const _MapPreviewFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_cardRadius),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: _rBlue10),
          borderRadius: BorderRadius.circular(_cardRadius),
        ),
        child: Stack(
          children: [
            SizedBox(height: 184, child: child),
            const Positioned.fill(child: _MapFade()),
          ],
        ),
      ),
    );
  }
}

class _StaticMapPreview extends StatelessWidget {
  const _StaticMapPreview({required this.route});

  final RunRouteSnapshot route;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: Key(_mapPreviewKeyFor(route)),
      painter: _MapPreviewPainter(route: route),
      child: const SizedBox.expand(),
    );
  }
}

class _ExpandedRouteMapScreen extends StatelessWidget {
  const _ExpandedRouteMapScreen({
    required this.routeName,
    required this.route,
    this.mapboxAccessToken,
    this.mapboxBuilder,
  });

  final String routeName;
  final RunRouteSnapshot route;
  final String? mapboxAccessToken;
  final CompletedRouteMapboxBuilder? mapboxBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('summary_route_expanded_screen'),
      backgroundColor: _rWhite,
      body: Stack(
        children: [
          Positioned.fill(
            child: CompletedRouteMapSurface(
              route: route,
              mapboxAccessToken: mapboxAccessToken,
              mapboxBuilder: mapboxBuilder,
              isExpanded: true,
              fallback: _ExpandedStaticRouteMap(route: route),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        routeName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _rBlue,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: _rWhite,
                        shape: BoxShape.circle,
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x242F51C8),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: IconButton(
                        key: const Key('summary_route_expanded_close'),
                        tooltip: 'Close route map',
                        onPressed: () => Navigator.of(context).pop(),
                        color: _rBlue,
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpandedStaticRouteMap extends StatelessWidget {
  const _ExpandedStaticRouteMap({required this.route});

  final RunRouteSnapshot route;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      key: Key('${_mapPreviewKeyFor(route)}_expanded'),
      painter: _MapPreviewPainter(route: route),
      child: const SizedBox.expand(),
    );
  }
}

String _mapPreviewKeyFor(RunRouteSnapshot route) {
  if (route.hasRoute) {
    return 'summary_route_preview_route';
  }
  if (route.hasLocation) {
    return 'summary_route_preview_dot';
  }
  return 'summary_route_preview_placeholder';
}

class _MapFade extends StatelessWidget {
  const _MapFade();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00F8FAFF), Color(0x8CF8FAFF)],
          stops: [0.6, 1],
        ),
      ),
    );
  }
}
