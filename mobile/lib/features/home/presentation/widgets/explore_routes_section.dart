import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../data/home_dashboard_demo_snapshots.dart';

const _routeCardGap = 12.0;
const _routeCardRadius = 20.0;
const _routeVisualHeight = 140.0;

/// The "explore routes" strip on Home — a horizontal row of suggested routes.
///
/// Each card's route shape is painted from its own points ([_RouteVisual])
/// rather than loaded as an image, so the strip scrolls without any map tiles
/// and costs Home nothing on first paint.
class ExploreRoutesSection extends StatelessWidget {
  const ExploreRoutesSection({
    this.routes = homeExploreRouteDemoSnapshots,
    super.key,
  });

  final List<HomeExploreRouteDemoSnapshot> routes;

  void _showPreviewMessage(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Route explorer preview')));
  }

  @override
  Widget build(BuildContext context) {
    return _HomeDividerSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    const Icon(
                      Icons.route_outlined,
                      color: RuniacColors.primaryBlue,
                      size: 27,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: const Text(
                          'Explore Routes',
                          maxLines: 1,
                          style: TextStyle(
                            color: RuniacColors.textPrimary,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: RuniacColors.textPrimary,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(64, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                onPressed: () => _showPreviewMessage(context),
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final rawWidth = constraints.maxWidth * 0.86;
              final cardWidth = math
                  .min(math.max(rawWidth, 250), 292)
                  .toDouble();

              return SizedBox(
                height: 232,
                child: ScrollConfiguration(
                  behavior: ScrollConfiguration.of(
                    context,
                  ).copyWith(overscroll: false),
                  child: ListView.separated(
                    key: const ValueKey('home_explore_routes_carousel'),
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.zero,
                    itemCount: routes.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: _routeCardGap),
                    itemBuilder: (context, index) {
                      return _ExploreRouteCard(
                        route: routes[index],
                        width: cardWidth,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HomeDividerSection extends StatelessWidget {
  const _HomeDividerSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RuniacColors.white,
        border: Border.symmetric(
          horizontal: BorderSide(color: RuniacColors.border),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 16, 0, 18),
        child: child,
      ),
    );
  }
}

class _ExploreRouteCard extends StatelessWidget {
  const _ExploreRouteCard({required this.route, required this.width});

  final HomeExploreRouteDemoSnapshot route;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: RuniacColors.white,
        borderRadius: BorderRadius.circular(_routeCardRadius),
        border: Border.all(color: RuniacColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: RuniacColors.softCardShadow,
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_routeCardRadius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _RouteVisual(distance: route.distance),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RuniacColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    route.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: RuniacColors.textSecondary,
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteVisual extends StatelessWidget {
  const _RouteVisual({required this.distance});

  final String distance;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _routeVisualHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFEAF4FF), Color(0xFFF8FBF2)],
              ),
            ),
          ),
          Positioned(
            left: -24,
            right: -18,
            bottom: -34,
            child: Container(
              height: 98,
              decoration: BoxDecoration(
                color: const Color(0xFFDDEFD2),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 20,
            bottom: 18,
            top: 22,
            child: CustomPaint(painter: const _RoutePathPainter()),
          ),
          const Positioned(
            left: 42,
            bottom: 34,
            child: _RouteMarker(color: RuniacColors.primaryBlue),
          ),
          const Positioned(
            right: 48,
            top: 34,
            child: _RouteMarker(color: RuniacColors.accentOrange),
          ),
          Positioned(
            left: 16,
            bottom: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: RuniacColors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: RuniacColors.cardBorder),
                boxShadow: const [
                  BoxShadow(
                    color: RuniacColors.softCardShadow,
                    blurRadius: 10,
                    offset: Offset(0, 5),
                  ),
                ],
              ),
              child: Text(
                distance,
                style: const TextStyle(
                  color: RuniacColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteMarker extends StatelessWidget {
  const _RouteMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: RuniacColors.white, width: 2),
      ),
    );
  }
}

class _RoutePathPainter extends CustomPainter {
  const _RoutePathPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(12, size.height * 0.76)
      ..cubicTo(
        size.width * 0.25,
        size.height * 0.48,
        size.width * 0.46,
        size.height * 0.98,
        size.width * 0.64,
        size.height * 0.55,
      )
      ..cubicTo(
        size.width * 0.75,
        size.height * 0.28,
        size.width * 0.88,
        size.height * 0.22,
        size.width - 10,
        size.height * 0.28,
      );

    final shadowPaint = Paint()
      ..color = RuniacColors.white.withValues(alpha: 0.82)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 13
      ..strokeCap = StrokeCap.round;

    final pathPaint = Paint()
      ..color = RuniacColors.primaryBlue.withValues(alpha: 0.84)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    canvas
      ..drawPath(path, shadowPaint)
      ..drawPath(path, pathPaint);
  }

  @override
  bool shouldRepaint(covariant _RoutePathPainter oldDelegate) => false;
}
