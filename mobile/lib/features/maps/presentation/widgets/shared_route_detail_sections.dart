import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import 'shared_route_detail_painters.dart';

// The body sections of the shared-route detail screen — hero, metric strip,
// elevation and runner notes.
//
// The `routeDetail*` constants below are the static/offline content for this
// screen. They are exported rather than inlined so the widget tests assert
// against the same strings the app renders, instead of duplicating copy that
// can drift.

const routeDetailTitle = 'Marina Bay easy loop';
const routeDetailTagLine = 'EASY \u00B7 LOOP';
const routeDetailLikeSummary = '128';
const routeDetailSharePayload = 'Marina Bay easy loop, 3.2 km, route link';
const routeDetailSignInFailureCopy = 'Sign in to select this route.';
const routeDetailOfflineFailureCopy =
    "You seem to be offline. Try again when you're connected.";
const routeDetailGenericFailureCopy =
    "We couldn't select this route. Please try again.";

class RouteDetailAccentStrip extends StatelessWidget {
  const RouteDetailAccentStrip({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: RuniacColors.primaryBlue,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Container(
          width: 54,
          height: 4,
          decoration: BoxDecoration(
            color: RuniacColors.accentOrange,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class RouteDetailHero extends StatelessWidget {
  const RouteDetailHero({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          routeDetailTagLine,
          style: TextStyle(
            color: RuniacColors.accentOrange,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          routeDetailTitle,
          style: TextStyle(
            color: RuniacColors.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            Icon(
              Icons.favorite_border,
              color: RuniacColors.primaryBlue,
              size: 18,
            ),
            SizedBox(width: 6),
            Text(
              routeDetailLikeSummary,
              style: TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          height: 356,
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FF),
            border: Border.all(color: RuniacColors.border),
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0A172033),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: CustomPaint(
                  key: Key('shared_route_detail_map_painter'),
                  painter: RouteMapPainter(),
                ),
              ),
              RouteMetricStrip(),
            ],
          ),
        ),
      ],
    );
  }
}

class RouteMetricStrip extends StatelessWidget {
  const RouteMetricStrip({this.compact = false, super.key});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = const [
      ('DISTANCE', '3.2 km'),
      ('EST. TIME', '25 min'),
      ('DIFFICULTY', 'Easy'),
    ];
    return Container(
      height: compact ? 72 : 98,
      decoration: BoxDecoration(
        color: RuniacColors.white,
        border: const Border(top: BorderSide(color: RuniacColors.border)),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(compact ? 0 : 12),
        ),
      ),
      child: Row(
        children: [
          for (final item in items) ...[
            Expanded(
              child: _MetricCell(label: item.$1, value: item.$2),
            ),
            if (item != items.last)
              const SizedBox(
                height: 42,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: RuniacColors.border,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class RouteDetailElevationSection extends StatelessWidget {
  const RouteDetailElevationSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Elevation',
          style: TextStyle(
            color: RuniacColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 16),
        _ElevationCard(),
      ],
    );
  }
}

class RouteDetailRunnerNotes extends StatelessWidget {
  const RouteDetailRunnerNotes({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Runner notes',
          style: TextStyle(
            color: RuniacColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: RuniacColors.white,
            border: Border.all(color: RuniacColors.border),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            'Good to run in the evening - flat path, well-lit. Avoid around '
            '7:30 PM since it gets crowded near the waterfront.',
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 17,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class RouteDetailHiddenFailureCopy extends StatelessWidget {
  const RouteDetailHiddenFailureCopy({super.key});

  @override
  Widget build(BuildContext context) {
    return const Offstage(
      child: Text(
        '$routeDetailSignInFailureCopy $routeDetailOfflineFailureCopy '
        '$routeDetailGenericFailureCopy $routeDetailSharePayload',
      ),
    );
  }
}

class _MetricCell extends StatelessWidget {
  const _MetricCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF7F97EE),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(
            color: RuniacColors.textPrimary,
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ElevationCard extends StatelessWidget {
  const _ElevationCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 170,
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
      decoration: BoxDecoration(
        color: RuniacColors.white,
        border: Border.all(color: RuniacColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: CustomPaint(
              key: Key('shared_route_detail_elevation_painter'),
              painter: ElevationPainter(),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0 m', style: _axisTextStyle),
              Text('+18 m gain', style: _axisTextStyle),
              Text('3.2 km', style: _axisTextStyle),
            ],
          ),
        ],
      ),
    );
  }
}

const _axisTextStyle = TextStyle(
  color: Color(0xFF7F97EE),
  fontSize: 16,
  fontWeight: FontWeight.w800,
);
