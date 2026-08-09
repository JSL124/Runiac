import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runiac_app/core/assets/runiac_assets.dart';
import 'package:runiac_app/core/share/share_card_export_service.dart';
import 'package:runiac_app/core/widgets/runiac_checkerboard_painter.dart';
import 'package:runiac_app/core/widgets/runiac_share_bottom_sheet.dart';
import 'package:runiac_app/features/feed/data/feed_publish/feed_thumbnail_artifact.dart';
import 'package:runiac_app/features/run/domain/models/run_location_sample.dart';
import 'package:runiac_app/features/run/domain/models/run_route_snapshot.dart';
import 'package:runiac_app/features/run/domain/models/run_summary_snapshot.dart';
import 'package:runiac_app/features/you/presentation/widgets/activity_route_thumbnail_viewport.dart';

const _blue = Color(0xFF2F51C8);
const _orange = Color(0xFFFB6414);
const _ink = Color(0xFF16235C);
const _orange22 = Color(0x38FB6414);
// Solid-card surface: a clean, very light blue-tinted off-white so the blue
// wordmark logo (and its orange accent) stay legible, unlike the previous
// blue gradient which made the logo invisible.
const _cardSurface = Color(0xFFF7F9FF);
// Secondary/label text on the light solid-card surface: a muted blue-grey
// (mirrors the previous ~65%-alpha white-on-blue treatment, now on white).
const _secondaryInk = Color(0xFF6B7BB2);

// Layered white glow behind every text element on the transparent share
// card, so ink/blue text stays legible when the card is shared over any
// photo or the Instagram Stories dark-blue gradient backdrop.
const _transparentTextHalo = [
  Shadow(color: Color(0xE6FFFFFF), blurRadius: 3),
  Shadow(color: Color(0xB3FFFFFF), blurRadius: 10),
  Shadow(color: Color(0x80FFFFFF), blurRadius: 20),
];

// Fixed card aspect ratio (width / height) shared by the solid and
// transparent share cards, so the carousel page height and the width-capping
// math stay consistent between pages. Derived from the solid card's natural
// rendered proportions at its 258-logical-px design width: the content
// column sums to roughly 416px tall (top row ~16 + gap 14 + map 126 + gap 24
// + title block ~41 + gap 18 + hero metric ~70 + gap 22 + metric grid ~43,
// plus 42 of container padding), giving 258 / 416 ~= 0.62.
const double _cardAspectRatio = 129 / 208;
const double _cardDesignWidth = 258;

class ShareAchievementSheet extends StatefulWidget {
  const ShareAchievementSheet({
    super.key,
    required this.summary,
    this.mapArtifact,
    this.exportService = const ShareCardExportService(),
  });

  final RunSummarySnapshot summary;

  /// Seam for tests. Production always uses the default const instance; a test
  /// injects a failing one to prove an export failure still reaches the runner
  /// as a message rather than silently doing nothing.
  final ShareCardExportService exportService;

  // Resolved by the call site (view_summary_screen) from the same
  // route-thumbnail pipeline used to publish to Feed, so the map panel shows
  // the runner's real route rather than a fake preview. Null when the run
  // has no route to preview.
  final Future<FeedThumbnailArtifact?>? mapArtifact;

  @override
  State<ShareAchievementSheet> createState() => _ShareAchievementSheetState();
}

class _ShareAchievementSheetState extends State<ShareAchievementSheet> {
  ShareCardExportService get _export => widget.exportService;

  final PageController _pageController = PageController();
  final GlobalKey _solidBoundaryKey = GlobalKey();
  final GlobalKey _transparentBoundaryKey = GlobalKey();
  int _currentPage = 0;
  // While true the transparent card hides its checkerboard preview backdrop so
  // the rasterized PNG keeps true alpha.
  bool _capturing = false;
  // While true an export action (save / share / instagram) is in flight; the
  // sheet shows a spinner and disables the targets so a tap reads as handled.
  bool _busy = false;
  // Whether Instagram Stories can actually be opened from this device (iOS
  // with Instagram installed). Probed once on init so the target renders
  // disabled rather than failing on tap. Optimistically true until the probe
  // answers, so the button never flickers from enabled to disabled.
  bool _instagramAvailable = true;
  // Transient confirmation shown inside the sheet. A SnackBar would render at
  // the screen bottom, hidden behind this modal sheet, so feedback lives here.
  String? _toast;
  Timer? _toastTimer;
  // Resolved from widget.mapArtifact once the future completes, so the real
  // map screenshot can pop in after the sheet has already opened.
  FeedThumbnailArtifact? _mapArtifact;
  // Decoded once and painted with pure Canvas ops on the transparent card
  // (see _HaloedLogoPainter) instead of an ImageFiltered widget layer:
  // RenderRepaintBoundary.toImage on Impeller is known to drop
  // ImageFilterLayer subtrees from the captured PNG, silently vanishing the
  // logo from exports even though it renders in the live preview.
  ui.Image? _logoImage;
  ImageStream? _logoImageStream;
  late final ImageStreamListener _logoImageListener;

  @override
  void initState() {
    super.initState();
    _logoImageListener = ImageStreamListener((info, synchronousCall) {
      if (mounted) {
        setState(() => _logoImage = info.image);
      }
    });
    final logoImageStream = const AssetImage(
      RuniacAssets.runiacWordmarkLogo,
    ).resolve(ImageConfiguration.empty);
    _logoImageStream = logoImageStream;
    logoImageStream.addListener(_logoImageListener);

    final mapArtifactFuture = widget.mapArtifact;
    if (mapArtifactFuture != null) {
      mapArtifactFuture.then((artifact) {
        if (mounted) {
          setState(() => _mapArtifact = artifact);
        }
      });
    }

    _export.isInstagramStoryAvailable().then((available) {
      if (mounted) {
        setState(() => _instagramAvailable = available);
      }
    });
  }

  void _showToast(String message) {
    if (!mounted) {
      return;
    }
    setState(() => _toast = message);
    _toastTimer?.cancel();
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _toast = null);
      }
    });
  }

  /// Runs an export action with a visible busy state so a tap on a share target
  /// gives immediate feedback and cannot be double-fired.
  ///
  /// The catch is deliberate. Without it an export failure escaped as an
  /// unhandled async error: the spinner cleared and the tap produced no
  /// visible result whatsoever, which is how a broken capture path shipped
  /// unnoticed. Every failure must leave the runner with something to read.
  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
    } catch (error, stackTrace) {
      developer.log(
        'RUNIAC_SHARE activity export failed',
        name: 'ShareAchievementSheet',
        error: error,
        stackTrace: stackTrace,
      );
      _showToast('Could not share right now');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void dispose() {
    _logoImageStream?.removeListener(_logoImageListener);
    _toastTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String get _cardFileName {
    final safeTitle = widget.summary.title.toLowerCase().replaceAll(
      RegExp('[^a-z0-9]+'),
      '_',
    );
    return 'runiac_activity_$safeTitle.png';
  }

  String get _shareText =>
      'I ran ${widget.summary.distanceKm} km in ${widget.summary.duration} '
      'at ${widget.summary.avgPace} pace on Runiac.';

  Future<Uint8List?> _captureCurrentCard() async {
    final isTransparent = _currentPage == 1;
    if (isTransparent) {
      setState(() => _capturing = true);
      await WidgetsBinding.instance.endOfFrame;
    }
    final bytes = await _export.capturePng(
      isTransparent ? _transparentBoundaryKey : _solidBoundaryKey,
    );
    if (isTransparent && mounted) {
      setState(() => _capturing = false);
    }
    return bytes;
  }

  Future<void> _saveCard() async {
    final bytes = await _captureCurrentCard();
    if (bytes == null) {
      _showToast('Could not render the card');
      return;
    }
    final saved = await _export.saveToGallery(bytes, fileName: _cardFileName);
    _showToast(saved ? 'Saved to your gallery' : 'Allow photo access to save');
  }

  Future<void> _shareCard() async {
    final bytes = await _captureCurrentCard();
    if (bytes == null) {
      _showToast('Could not render the card');
      return;
    }
    await _export.shareViaSheet(
      bytes,
      fileName: _cardFileName,
      text: _shareText,
    );
  }

  Future<void> _shareToInstagram() async {
    final bytes = await _captureCurrentCard();
    if (bytes == null) {
      _showToast('Could not render the card');
      return;
    }
    // Placeholder Facebook App ID by default so Instagram sharing works in
    // testing without a dart-define; override with a real Meta App ID via
    // --dart-define=INSTAGRAM_FB_APP_ID=... for production.
    const appId = String.fromEnvironment(
      'INSTAGRAM_FB_APP_ID',
      defaultValue: '000000000000000',
    );
    final shared = await _export.shareToInstagramStory(bytes, appId: appId);
    if (!shared) {
      _showToast('Couldn\'t open Instagram Stories');
    }
  }

  Future<void> _copyLink() async {
    final bytes = await _captureCurrentCard();
    if (bytes == null) {
      _showToast('Could not render the card');
      return;
    }
    final url = await _export.uploadShareCardLink(
      bytes,
      storageFileName: 'activity-card.png',
    );
    if (url == null) {
      _showToast('Sign in to copy a share link');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _showToast('Link copied to clipboard');
  }

  Future<void> _copyActivity() async {
    await Clipboard.setData(ClipboardData(text: _shareText));
    _showToast('Activity copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return RuniacShareBottomSheet(
      key: const Key('run_share_activity_sheet'),
      title: 'Share Your Activity',
      preview: LayoutBuilder(
        builder: (context, constraints) {
          // Cap the card width by the available preview height too, so the
          // fixed-aspect card plus page indicator always fit without a bottom
          // overflow on shorter screens.
          const belowCardExtent = 24.0 + 8.0 + 7.0;
          final availableCardHeight = (constraints.maxHeight - belowCardExtent)
              .clamp(0.0, double.infinity);
          final cardWidth = (MediaQuery.sizeOf(context).width * 0.88)
              .clamp(0.0, constraints.maxWidth)
              .clamp(0.0, availableCardHeight * _cardAspectRatio)
              .toDouble();
          final cardHeight = cardWidth == 0
              ? 0.0
              : cardWidth / _cardAspectRatio;

          return Stack(
            children: [
              SizedBox(
                height: constraints.maxHeight,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          // Full-width so the carousel swipe gesture spans the
                          // sheet; each page centers its card at [cardWidth].
                          width: constraints.maxWidth,
                          height: cardHeight,
                          child: PageView(
                            key: const Key('run_share_activity_carousel'),
                            controller: _pageController,
                            onPageChanged: (page) {
                              setState(() => _currentPage = page);
                            },
                            children: [
                              Center(
                                child: SizedBox(
                                  key: const Key(
                                    'run_share_activity_card_solid',
                                  ),
                                  width: cardWidth,
                                  height: cardHeight,
                                  child: FittedBox(
                                    fit: BoxFit.contain,
                                    child: RepaintBoundary(
                                      key: _solidBoundaryKey,
                                      child: _ShareActivityCardSurface(
                                        summary: widget.summary,
                                        mapArtifact: _mapArtifact,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Center(
                                child: SizedBox(
                                  width: cardWidth,
                                  child: RepaintBoundary(
                                    key: _transparentBoundaryKey,
                                    child: _ShareActivityTransparentCard(
                                      summary: widget.summary,
                                      showBackdrop: !_capturing,
                                      logoImage: _logoImage,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ShareActivityPageIndicator(
                          count: 2,
                          activeIndex: _currentPage,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_busy)
                Positioned.fill(
                  child: AbsorbPointer(
                    child: ColoredBox(
                      color: Colors.white.withValues(alpha: 0.6),
                      child: const Center(
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: _blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_toast != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 8,
                  child: IgnorePointer(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _ink.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _toast!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      shareTargets: [
        RuniacShareTargetButton(
          key: const Key('run_share_activity_instagram_action'),
          icon: Icons.camera_alt_outlined,
          iconAsset: RuniacAssets.instagramStoriesIcon,
          label: 'Instagram',
          enabled: !_busy && _instagramAvailable,
          onPressed: () => _runBusy(_shareToInstagram),
        ),
        RuniacShareTargetButton(
          key: const Key('run_share_activity_copy_action'),
          icon: Icons.content_paste_outlined,
          label: 'Copy to Clipboard',
          enabled: !_busy,
          onPressed: _copyActivity,
        ),
        RuniacShareTargetButton(
          key: const Key('run_share_activity_save_action'),
          icon: Icons.file_download_outlined,
          label: 'Save',
          enabled: !_busy,
          onPressed: () => _runBusy(_saveCard),
        ),
        RuniacShareTargetButton(
          key: const Key('run_share_activity_copy_link_action'),
          icon: Icons.link,
          label: 'Copy Link',
          enabled: !_busy,
          onPressed: () => _runBusy(_copyLink),
        ),
        RuniacShareTargetButton(
          key: const Key('run_share_activity_more_action'),
          icon: Icons.more_horiz,
          label: 'More',
          enabled: !_busy,
          onPressed: () => _runBusy(_shareCard),
        ),
      ],
    );
  }
}

class _ShareActivityPageIndicator extends StatelessWidget {
  const _ShareActivityPageIndicator({
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('run_share_activity_page_indicator'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _ShareActivityIndicatorDot(active: i == activeIndex),
        ],
      ],
    );
  }
}

class _ShareActivityIndicatorDot extends StatelessWidget {
  const _ShareActivityIndicatorDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? _blue : _blue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(width: active ? 18 : 7, height: 7),
    );
  }
}

// The solid share card: gradient card body showing only trusted display
// strings read from [RunSummarySnapshot]. The client never computes XP,
// level, rank, streak, or leaderboard values here.
class _ShareActivityCardSurface extends StatelessWidget {
  const _ShareActivityCardSurface({required this.summary, this.mapArtifact});

  final RunSummarySnapshot summary;
  final FeedThumbnailArtifact? mapArtifact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _cardDesignWidth,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 20),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(26)),
        color: _cardSurface,
        boxShadow: [
          BoxShadow(
            color: Color(0x1F16235C),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ShareCardTopRow(dateTimeLabel: summary.dateTimeLabel),
              const SizedBox(height: 14),
              RoutePreviewPanel(
                routeName: summary.routeName,
                route: summary.route,
                mapArtifact: mapArtifact,
              ),
              const SizedBox(height: 24),
              _ShareCardTitleBlock(
                title: summary.title,
                supportiveLine: summary.coachingSummary.headline,
              ),
              const SizedBox(height: 18),
              _HeroMetric(distanceKm: summary.distanceKm),
              const SizedBox(height: 22),
              _ShareMetricGrid(
                avgPace: summary.avgPace,
                duration: summary.duration,
                avgHeartRate: summary.avgHeartRate,
                calories: summary.calories,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShareCardTopRow extends StatelessWidget {
  const _ShareCardTopRow({required this.dateTimeLabel});

  final String dateTimeLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Image.asset(
          RuniacAssets.runiacWordmarkLogo,
          height: 20,
          fit: BoxFit.contain,
          alignment: Alignment.centerLeft,
        ),
        Flexible(
          child: Text(
            dateTimeLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: _secondaryInk,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

// Map panel: renders the real route thumbnail once resolved, otherwise a
// decorative gradient with the real GPS trace (or a location glyph when
// there is no route at all).
class RoutePreviewPanel extends StatelessWidget {
  const RoutePreviewPanel({
    super.key,
    required this.routeName,
    required this.route,
    this.mapArtifact,
  });

  final String routeName;
  final RunRouteSnapshot route;
  final FeedThumbnailArtifact? mapArtifact;

  @override
  Widget build(BuildContext context) {
    final artifact = mapArtifact;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Stack(
        children: [
          SizedBox(
            height: 126,
            width: double.infinity,
            child: artifact != null
                ? Image(
                    key: const Key('run_share_activity_map_image'),
                    image: artifact.memoryImage,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 126,
                  )
                : DecoratedBox(
                    key: const Key('run_share_activity_map_fallback'),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFFEAF0FF), Color(0xFFDCE6FF)],
                      ),
                    ),
                    child: route.hasRoute
                        ? CustomPaint(
                            painter: _ActivityRouteTracePainter(route),
                            child: const SizedBox.expand(),
                          )
                        : const Center(
                            child: Icon(
                              Icons.location_on_outlined,
                              color: _blue,
                              size: 28,
                            ),
                          ),
                  ),
          ),
          Positioned(
            left: 10,
            bottom: 11,
            // Plain semi-opaque surface, not a BackdropFilter blur: the pill
            // sits inside the same RepaintBoundary that gets rasterized for
            // export, and BackdropFilter is a layer-based effect that some
            // rendering backends drop from RenderRepaintBoundary.toImage
            // captures. The higher opacity compensates for losing the blur.
            child: Container(
              padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
              decoration: const BoxDecoration(
                color: Color(0xE8FFFFFF),
                borderRadius: BorderRadius.all(Radius.circular(99)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.location_pin, color: _orange, size: 13),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      routeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareCardTitleBlock extends StatelessWidget {
  const _ShareCardTitleBlock({
    required this.title,
    required this.supportiveLine,
  });

  final String title;
  final String supportiveLine;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SupportiveDot(),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                supportiveLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _secondaryInk,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SupportiveDot extends StatelessWidget {
  const _SupportiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: _orange,
        borderRadius: BorderRadius.circular(99),
        boxShadow: const [
          BoxShadow(color: _orange22, blurRadius: 0, spreadRadius: 3),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.distanceKm});

  final String distanceKm;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                distanceKm,
                style: const TextStyle(
                  color: _ink,
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontSize: 58,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -3.2,
                  height: 0.9,
                ),
              ),
              const SizedBox(width: 7),
              const Text(
                'km',
                style: TextStyle(
                  color: _secondaryInk,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Distance',
          style: TextStyle(
            color: _secondaryInk,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
      ],
    );
  }
}

class _ShareMetricGrid extends StatelessWidget {
  const _ShareMetricGrid({
    required this.avgPace,
    required this.duration,
    required this.avgHeartRate,
    required this.calories,
  });

  final String avgPace;
  final String duration;
  final String avgHeartRate;
  final String calories;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0x1F16235C))),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(
          children: [
            Expanded(
              child: _ShareMetric(value: avgPace, label: 'Avg pace'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ShareMetric(value: duration, label: 'Time'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ShareMetric(value: avgHeartRate, label: 'Avg HR'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ShareMetric(value: calories, label: 'Calories'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareMetric extends StatelessWidget {
  const _ShareMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontFeatures: [FontFeature.tabularFigures()],
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _secondaryInk,
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

// The transparent overlay card: same trusted display strings, no background
// fill, so it can be shared over the user's own photo (alpha preserved on
// export).
class _ShareActivityTransparentCard extends StatelessWidget {
  const _ShareActivityTransparentCard({
    required this.summary,
    this.showBackdrop = true,
    this.logoImage,
  });

  final RunSummarySnapshot summary;
  // The checkerboard preview backdrop is hidden during PNG capture so the
  // exported image keeps a genuinely transparent background.
  final bool showBackdrop;
  // Decoded once by the parent state and painted with pure Canvas ops (see
  // _HaloedLogoPainter) so the logo survives RenderRepaintBoundary.toImage.
  // Null for the first frame or two while the asset resolves; nothing is
  // painted in that slot until then.
  final ui.Image? logoImage;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _cardAspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardHeight = constraints.maxHeight;

            return Stack(
              key: const Key('run_share_activity_card_transparent'),
              fit: StackFit.expand,
              children: [
                if (showBackdrop)
                  Positioned.fill(
                    child: CustomPaint(
                      key: const Key('run_share_activity_transparent_sign'),
                      painter: const RuniacCheckerboardPainter(),
                    ),
                  ),
                if (summary.route.hasRoute)
                  // Middle band only, so the trace never overlaps the logo
                  // (top) or the stat block (bottom).
                  Positioned(
                    left: 0,
                    right: 0,
                    top: cardHeight * 0.20,
                    bottom: cardHeight * 0.30,
                    child: CustomPaint(
                      painter: _ActivityRouteTracePainter(summary.route),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: cardHeight * 0.055,
                  height: cardHeight * 0.14,
                  // Guaranteed-contrast halo, painted with pure Canvas ops
                  // (see _HaloedLogoPainter) so it always rasterizes into the
                  // RepaintBoundary capture, unlike an ImageFiltered widget
                  // layer. Left empty until the asset resolves.
                  child: logoImage == null
                      ? const SizedBox.shrink()
                      : CustomPaint(
                          key: const Key('run_share_activity_transparent_logo'),
                          painter: _HaloedLogoPainter(logoImage!),
                          child: const SizedBox.expand(),
                        ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: cardHeight * 0.19,
                  child: Center(
                    child: _TransparentDistanceHero(
                      distanceKm: summary.distanceKm,
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: cardHeight * 0.06,
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: _TransparentStatRow(
                        avgPace: summary.avgPace,
                        duration: summary.duration,
                        avgHeartRate: summary.avgHeartRate,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TransparentDistanceHero extends StatelessWidget {
  const _TransparentDistanceHero({required this.distanceKm});

  final String distanceKm;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            distanceKm,
            style: const TextStyle(
              color: _ink,
              fontFeatures: [FontFeature.tabularFigures()],
              fontSize: 46,
              fontWeight: FontWeight.w900,
              height: 0.94,
              shadows: _transparentTextHalo,
            ),
          ),
          const SizedBox(width: 6),
          const Text(
            'km',
            style: TextStyle(
              color: _blue,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              shadows: _transparentTextHalo,
            ),
          ),
        ],
      ),
    );
  }
}

class _TransparentStatRow extends StatelessWidget {
  const _TransparentStatRow({
    required this.avgPace,
    required this.duration,
    required this.avgHeartRate,
  });

  final String avgPace;
  final String duration;
  final String avgHeartRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TransparentStat(value: avgPace, label: 'Avg pace'),
        const SizedBox(width: 18),
        _TransparentStat(value: duration, label: 'Time'),
        const SizedBox(width: 18),
        _TransparentStat(value: avgHeartRate, label: 'Avg HR'),
      ],
    );
  }
}

class _TransparentStat extends StatelessWidget {
  const _TransparentStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          value,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _ink,
            fontFeatures: [FontFeature.tabularFigures()],
            fontSize: 17,
            fontWeight: FontWeight.w800,
            shadows: _transparentTextHalo,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _blue,
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
            shadows: _transparentTextHalo,
          ),
        ),
      ],
    );
  }
}

// Paints the wordmark logo with a layered white glow using pure Canvas
// drawImageRect calls only — no ImageFiltered/BackdropFilter/ShaderMask
// widget layers. RenderRepaintBoundary.toImage is known to drop
// ImageFilterLayer subtrees on some rendering backends (Impeller), which
// silently vanished the logo from exported PNGs even though it rendered in
// the live preview; picture-level canvas ops always rasterize into the
// capture.
class _HaloedLogoPainter extends CustomPainter {
  const _HaloedLogoPainter(this.logo);

  final ui.Image logo;

  @override
  void paint(Canvas canvas, Size size) {
    final dest = _containRect(logo, size);
    final src = Rect.fromLTWH(
      0,
      0,
      logo.width.toDouble(),
      logo.height.toDouble(),
    );

    // Pass 1: wide soft white glow.
    canvas.drawImageRect(
      logo,
      src,
      dest,
      Paint()
        ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
        ..filterQuality = FilterQuality.high,
    );
    // Pass 2: tighter white outline.
    canvas.drawImageRect(
      logo,
      src,
      dest,
      Paint()
        ..colorFilter = const ColorFilter.mode(Colors.white, BlendMode.srcIn)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5)
        ..filterQuality = FilterQuality.high,
    );
    // Pass 3: the real logo on top.
    canvas.drawImageRect(
      logo,
      src,
      dest,
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  Rect _containRect(ui.Image image, Size size) {
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();
    if (imageWidth <= 0 || imageHeight <= 0) {
      return Offset.zero & size;
    }
    final scale = math.min(size.width / imageWidth, size.height / imageHeight);
    final destWidth = imageWidth * scale;
    final destHeight = imageHeight * scale;
    return Rect.fromLTWH(
      (size.width - destWidth) / 2,
      (size.height - destHeight) / 2,
      destWidth,
      destHeight,
    );
  }

  @override
  bool shouldRepaint(covariant _HaloedLogoPainter oldDelegate) {
    return oldDelegate.logo != logo;
  }
}

// Draws the real GPS route trace for the share card map panel (solid-card
// fallback background) and the transparent card. Projects samples with
// [ActivityRouteThumbnailViewport], the same projection used by History and
// Feed thumbnails, so the traced route matches what the user already sees
// elsewhere in the app. Only trusted GPS samples already on the device are
// drawn; nothing here is computed by the client as a backend-owned value.
class _ActivityRouteTracePainter extends CustomPainter {
  const _ActivityRouteTracePainter(this.route);

  final RunRouteSnapshot route;

  @override
  void paint(Canvas canvas, Size size) {
    final viewport = ActivityRouteThumbnailViewport.fromRoute(
      route,
      logicalSize: size,
    );
    if (viewport.mode != ActivityRouteThumbnailViewportMode.meaningfulRoute) {
      return;
    }

    // White casing drawn first, under the glow and route strokes, so the
    // polyline stays visible against dark photos or the Instagram Stories
    // dark-blue gradient backdrop (mirrors the text/logo halo treatment).
    final casingPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.95)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final glowPaint = Paint()
      ..color = const Color(0x382F51C8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    final routePaint = Paint()
      ..color = _blue
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    RunLocationSample? firstPoint;
    RunLocationSample? lastPoint;
    for (final segment in route.segments) {
      final path = _pathForSegment(segment, viewport);
      if (path == null) {
        continue;
      }
      canvas.drawPath(path, casingPaint);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, routePaint);
      final drawable = segment
          .where((point) => point.latitude.isFinite && point.longitude.isFinite)
          .toList(growable: false);
      firstPoint ??= drawable.first;
      lastPoint = drawable.last;
    }

    if (firstPoint != null) {
      final start = viewport.project(firstPoint);
      canvas.drawCircle(start, 7.5, Paint()..color = Colors.white);
      canvas.drawCircle(start, 5, Paint()..color = _blue);
    }
    if (lastPoint != null) {
      final finish = viewport.project(lastPoint);
      canvas.drawCircle(finish, 8.2, Paint()..color = Colors.white);
      canvas.drawCircle(finish, 5.4, Paint()..color = _orange);
    }
  }

  Path? _pathForSegment(
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
    final path = Path()..moveTo(start.dx, start.dy);
    for (final point in points.skip(1)) {
      final projected = viewport.project(point);
      path.lineTo(projected.dx, projected.dy);
    }
    return path;
  }

  @override
  bool shouldRepaint(covariant _ActivityRouteTracePainter oldDelegate) {
    return oldDelegate.route != route;
  }
}
