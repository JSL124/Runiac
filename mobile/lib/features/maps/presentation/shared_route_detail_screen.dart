import 'package:flutter/material.dart';

import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import 'widgets/shared_route_detail_actions.dart';
import 'widgets/shared_route_detail_painters.dart';
import 'widgets/shared_route_detail_sections.dart';

/// One shared route in full: its shape, its metrics, and what can be done with
/// it — save, share or report.
///
/// The screen takes a [SharedRouteDetailSnapshot] rather than fetching, because
/// it is reached from several places (the map sheet, saved routes, a feed post)
/// that have already loaded the route. Reporting matters here: a shared route
/// is user-generated content, so the report path feeds the admin console's
/// Exception Queue.
class SharedRouteDetailSnapshot {
  const SharedRouteDetailSnapshot({
    required this.title,
    required this.distance,
    required this.duration,
    required this.difficulty,
    this.likeCountLabel = routeDetailLikeSummary,
  });

  static const defaultRoute = SharedRouteDetailSnapshot(
    title: routeDetailTitle,
    distance: '3.2 km',
    duration: '25 min',
    difficulty: 'Easy',
    likeCountLabel: routeDetailLikeSummary,
  );

  final String title;
  final String distance;
  final String duration;
  final String difficulty;
  final String likeCountLabel;

  String get meta => '$distance · $duration · $difficulty';
  String get tagLine => '${difficulty.toUpperCase()} · LOOP';
}

class SharedRouteDetailScreen extends StatefulWidget {
  const SharedRouteDetailScreen({
    this.route = SharedRouteDetailSnapshot.defaultRoute,
    super.key,
  });

  final SharedRouteDetailSnapshot route;

  @override
  State<SharedRouteDetailScreen> createState() =>
      _SharedRouteDetailScreenState();
}

class _SharedRouteDetailScreenState extends State<SharedRouteDetailScreen> {
  bool _isBookmarked = false;
  bool _isLiked = false;
  bool _isSaving = false;
  bool _isSelected = false;

  Future<void> _confirmRouteSelection() async {
    Navigator.of(context).pop();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    setState(() => _isSaving = true);
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _isBookmarked = true;
      _isSelected = true;
    });
    _showSuccessSheet();
  }

  void _showConfirmSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: RuniacColors.white,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Select this route?',
                style: TextStyle(
                  color: RuniacColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'This will replace your current selected route.',
                style: TextStyle(
                  color: RuniacColors.textSecondary,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              _RouteMetricStrip(route: widget.route, compact: true),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _confirmRouteSelection,
                style: RuniacButtonStyles.primary(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text('Confirm Route'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSuccessSheet() {
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: RuniacColors.white,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Route selected',
                style: TextStyle(
                  color: RuniacColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'This route has been saved and set for your next run.',
                style: TextStyle(
                  color: RuniacColors.textSecondary,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: RuniacButtonStyles.primary(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Start Run'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('View Planned Routes'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Stay Here'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSharePreviewSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: RuniacColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return RouteDetailSharePreviewSheet(
          onClose: () => Navigator.of(context).pop(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: RuniacColors.white,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                RuniacBackHeader(
                  title: 'Route',
                  height: 64,
                  titleStyle: const TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  trailing: Semantics(
                    label: 'Share route',
                    button: true,
                    child: IconButton(
                      tooltip: 'Share route',
                      onPressed: _showSharePreviewSheet,
                      icon: const Icon(Icons.share_outlined),
                      color: RuniacColors.primaryBlue,
                    ),
                  ),
                ),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(
                      context,
                    ).copyWith(overscroll: false),
                    child: ListView(
                      key: const Key('shared_route_detail_scroll_view'),
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
                      children: [
                        const RouteDetailAccentStrip(),
                        const SizedBox(height: 14),
                        _RouteDetailHero(
                          route: widget.route,
                          isLiked: _isLiked,
                          onLike: () => setState(() => _isLiked = !_isLiked),
                        ),
                        const SizedBox(height: 24),
                        const RouteDetailElevationSection(),
                        const SizedBox(height: 26),
                        const RouteDetailRunnerNotes(),
                        const SizedBox(height: 12),
                        const RouteDetailHiddenFailureCopy(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: RouteDetailBottomActionBar(
              isBookmarked: _isBookmarked,
              onBookmark: () => setState(() => _isBookmarked = !_isBookmarked),
              onSelectRoute: _isSelected ? null : _showConfirmSheet,
            ),
          ),
          if (_isSaving) const RouteDetailSavingOverlay(),
        ],
      ),
    );
  }
}

class _RouteDetailHero extends StatelessWidget {
  const _RouteDetailHero({
    required this.route,
    required this.isLiked,
    required this.onLike,
  });

  final SharedRouteDetailSnapshot route;
  final bool isLiked;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          route.tagLine,
          style: const TextStyle(
            color: RuniacColors.accentOrange,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          route.title,
          style: const TextStyle(
            color: RuniacColors.textPrimary,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            IconButton(
              key: const Key('shared_route_detail_like_action'),
              tooltip: isLiked ? 'Unlike route' : 'Like route',
              onPressed: onLike,
              icon: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: RuniacColors.primaryBlue,
                size: 22,
              ),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
            const SizedBox(width: 4),
            Text(
              route.likeCountLabel,
              style: const TextStyle(
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(
                child: CustomPaint(
                  key: Key('shared_route_detail_map_painter'),
                  painter: RouteMapPainter(),
                ),
              ),
              _RouteMetricStrip(route: route),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteMetricStrip extends StatelessWidget {
  const _RouteMetricStrip({required this.route, this.compact = false});

  final SharedRouteDetailSnapshot route;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('DISTANCE', route.distance),
      ('EST. TIME', route.duration),
      ('DIFFICULTY', route.difficulty),
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
