import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/assets/runiac_assets.dart';
import '../../../../core/share/share_card_export_service.dart';
import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_checkerboard_painter.dart';
import '../../../../core/widgets/runiac_share_bottom_sheet.dart';

// Fixed card aspect ratio shared by the solid and transparent share cards so
// the carousel page height and the width capping math stay consistent.
const double _cardAspectRatio = 1122 / 1402;

class ShareRankFloatingPanel extends StatefulWidget {
  const ShareRankFloatingPanel({
    super.key,
    required this.regionName,
    required this.divisionName,
    required this.rankLabel,
    required this.leagueBadgeAssetPath,
    this.exportService = const ShareCardExportService(),
  });

  /// Seam for tests. Production always uses the default const instance; a test
  /// injects a failing one to prove an export failure still reaches the runner
  /// as a message rather than silently doing nothing.
  final ShareCardExportService exportService;

  final String regionName;
  final String divisionName;
  final String rankLabel;
  // League (division) badge artwork resolved from the trusted board division.
  // Display-only; the client never computes the division.
  final String leagueBadgeAssetPath;

  @override
  State<ShareRankFloatingPanel> createState() => _ShareRankFloatingPanelState();
}

class _ShareRankFloatingPanelState extends State<ShareRankFloatingPanel> {
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
  // Transient confirmation shown inside the sheet. A SnackBar would render at
  // the screen bottom, hidden behind this modal sheet, so feedback lives here.
  String? _toast;
  Timer? _toastTimer;
  // Whether Instagram Stories can actually be opened from this device (iOS
  // with Instagram installed). Probed once on init so the target renders
  // disabled rather than failing on tap. Optimistically true until the probe
  // answers, so the button never flickers from enabled to disabled.
  bool _instagramAvailable = true;

  @override
  void initState() {
    super.initState();
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
        'RUNIAC_SHARE rank export failed',
        name: 'ShareRankFloatingPanel',
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
    _toastTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  String get _cardFileName {
    final safeRank = widget.rankLabel.replaceAll(RegExp('[^A-Za-z0-9]'), '');
    return 'runiac_rank_$safeRank.png';
  }

  String get _shareText =>
      'I\'m ranked ${widget.rankLabel} in ${widget.regionName}\'s '
      '${widget.divisionName} on Runiac.';

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
      storageFileName: 'rank-card.png',
    );
    if (url == null) {
      _showToast('Sign in to copy a share link');
      return;
    }
    await Clipboard.setData(ClipboardData(text: url));
    _showToast('Link copied to clipboard');
  }

  Future<void> _copyRank() async {
    await Clipboard.setData(
      ClipboardData(
        text:
            'I\'m ranked ${widget.rankLabel} in ${widget.regionName}\'s '
            '${widget.divisionName} on Runiac.',
      ),
    );
    _showToast('Rank copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return RuniacShareBottomSheet(
      key: const Key('leaderboard_share_rank_panel'),
      title: 'Share your rank',
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
                            key: const Key('leaderboard_share_rank_carousel'),
                            controller: _pageController,
                            onPageChanged: (page) {
                              setState(() => _currentPage = page);
                            },
                            children: [
                              Center(
                                child: SizedBox(
                                  width: cardWidth,
                                  child: RepaintBoundary(
                                    key: _solidBoundaryKey,
                                    child: _ShareRankCardPreview(
                                      regionName: widget.regionName,
                                      divisionName: widget.divisionName,
                                      rankLabel: widget.rankLabel,
                                      leagueBadgeAssetPath:
                                          widget.leagueBadgeAssetPath,
                                    ),
                                  ),
                                ),
                              ),
                              Center(
                                child: SizedBox(
                                  width: cardWidth,
                                  child: RepaintBoundary(
                                    key: _transparentBoundaryKey,
                                    child: _ShareRankTransparentCard(
                                      regionName: widget.regionName,
                                      divisionName: widget.divisionName,
                                      rankLabel: widget.rankLabel,
                                      leagueBadgeAssetPath:
                                          widget.leagueBadgeAssetPath,
                                      showBackdrop: !_capturing,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ShareRankPageIndicator(
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
                      color: RuniacColors.white.withValues(alpha: 0.6),
                      child: const Center(
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: RuniacColors.primaryBlue,
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
                          color: RuniacColors.textPrimary.withValues(
                            alpha: 0.92,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _toast!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: RuniacColors.white,
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
          key: const Key('leaderboard_instagram_rank_action'),
          icon: Icons.camera_alt_outlined,
          iconAsset: RuniacAssets.instagramStoriesIcon,
          label: 'Instagram',
          enabled: !_busy && _instagramAvailable,
          onPressed: () => _runBusy(_shareToInstagram),
        ),
        RuniacShareTargetButton(
          key: const Key('leaderboard_copy_rank_action'),
          icon: Icons.content_paste_outlined,
          label: 'Copy to Clipboard',
          enabled: !_busy,
          onPressed: _copyRank,
        ),
        RuniacShareTargetButton(
          key: const Key('leaderboard_save_rank_action'),
          icon: Icons.file_download_outlined,
          label: 'Save',
          enabled: !_busy,
          onPressed: () => _runBusy(_saveCard),
        ),
        RuniacShareTargetButton(
          key: const Key('leaderboard_copy_link_action'),
          icon: Icons.link,
          label: 'Copy Link',
          enabled: !_busy,
          onPressed: () => _runBusy(_copyLink),
        ),
        RuniacShareTargetButton(
          key: const Key('leaderboard_share_rank_more_action'),
          icon: Icons.more_horiz,
          label: 'More',
          enabled: !_busy,
          onPressed: () => _runBusy(_shareCard),
        ),
      ],
    );
  }
}

class _ShareRankPageIndicator extends StatelessWidget {
  const _ShareRankPageIndicator({
    required this.count,
    required this.activeIndex,
  });

  final int count;
  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('leaderboard_share_rank_page_indicator'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          _ShareRankIndicatorDot(active: i == activeIndex),
        ],
      ],
    );
  }
}

class _ShareRankIndicatorDot extends StatelessWidget {
  const _ShareRankIndicatorDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: active
          ? const Key('leaderboard_share_rank_indicator_dot_active')
          : const Key('leaderboard_share_rank_indicator_dot_inactive'),
      decoration: BoxDecoration(
        color: active
            ? RuniacColors.primaryBlue
            : RuniacColors.primaryBlue.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(width: active ? 18 : 7, height: 7),
    );
  }
}

// The solid share card: baked artwork background plus the shared card body.
class _ShareRankCardPreview extends StatelessWidget {
  const _ShareRankCardPreview({
    required this.regionName,
    required this.divisionName,
    required this.rankLabel,
    required this.leagueBadgeAssetPath,
  });

  final String regionName;
  final String divisionName;
  final String rankLabel;
  final String leagueBadgeAssetPath;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _cardAspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          key: const Key('leaderboard_share_rank_card_solid'),
          fit: StackFit.expand,
          children: [
            Image.asset(
              RuniacAssets.leaderboardShareRankCardBackground,
              key: const Key('leaderboard_share_rank_card_background'),
              fit: BoxFit.cover,
            ),
            _ShareRankCardBody(
              regionName: regionName,
              divisionName: divisionName,
              rankLabel: rankLabel,
              leagueBadgeAssetPath: leagueBadgeAssetPath,
            ),
          ],
        ),
      ),
    );
  }
}

// The transparent overlay card: identical components with no background fill,
// so it can be shared over the user's own photo (alpha preserved on export).
class _ShareRankTransparentCard extends StatelessWidget {
  const _ShareRankTransparentCard({
    required this.regionName,
    required this.divisionName,
    required this.rankLabel,
    required this.leagueBadgeAssetPath,
    this.showBackdrop = true,
  });

  final String regionName;
  final String divisionName;
  final String rankLabel;
  final String leagueBadgeAssetPath;
  // The checkerboard preview backdrop is hidden during PNG capture so the
  // exported image keeps a genuinely transparent background.
  final bool showBackdrop;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: _cardAspectRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = constraints.maxWidth;
            final cardHeight = constraints.maxHeight;

            return Stack(
              key: const Key('leaderboard_share_rank_card_transparent'),
              fit: StackFit.expand,
              children: [
                // Checkerboard backdrop is the "transparent background" sign in
                // the preview; hidden during capture so the exported PNG keeps
                // true alpha and overlays the user's own photo.
                if (showBackdrop)
                  Positioned.fill(
                    child: CustomPaint(
                      key: const Key('leaderboard_share_rank_transparent_sign'),
                      painter: const RuniacCheckerboardPainter(),
                    ),
                  ),
                // Laurel wreath, sparkle dividers, and running-man divider,
                // redrawn here to mirror the solid card whose decorations are
                // baked into its background art.
                const Positioned.fill(
                  key: Key('leaderboard_share_rank_transparent_decorations'),
                  child: _ShareRankTransparentDecorations(),
                ),
                // Runiac logo at the top, matching the solid card whose logo is
                // baked into its background art.
                Positioned(
                  left: cardWidth * 0.14,
                  right: cardWidth * 0.14,
                  top: cardHeight * 0.11,
                  height: cardHeight * 0.16,
                  child: Image.asset(
                    RuniacAssets.runiacWordmarkLogo,
                    key: const Key('leaderboard_share_rank_transparent_logo'),
                    fit: BoxFit.contain,
                  ),
                ),
                _ShareRankCardBody(
                  regionName: regionName,
                  divisionName: divisionName,
                  rankLabel: rankLabel,
                  leagueBadgeAssetPath: leagueBadgeAssetPath,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// Vector decorations for the transparent card: two sparkle dividers, a
// running-man divider, and a laurel wreath framing the rank. These live only
// on the transparent card; the solid card gets them from its baked artwork.
class _ShareRankTransparentDecorations extends StatelessWidget {
  const _ShareRankTransparentDecorations();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          fit: StackFit.expand,
          children: [
            // Top sparkle divider, between the logo and the region.
            Positioned(
              left: w * 0.16,
              right: w * 0.16,
              top: h * 0.305,
              height: h * 0.03,
              child: _SparkleDivider(starSize: h * 0.028),
            ),
            // Running-man divider, between the league and the rank.
            Positioned(
              left: w * 0.16,
              right: w * 0.16,
              top: h * 0.485,
              height: h * 0.05,
              child: _RunnerDivider(iconSize: h * 0.045),
            ),
            // Bottom sparkle divider, at the base of the wreath.
            Positioned(
              left: w * 0.30,
              right: w * 0.30,
              top: h * 0.79,
              height: h * 0.03,
              child: _SparkleDivider(starSize: h * 0.024),
            ),
          ],
        );
      },
    );
  }
}

class _SparkleDivider extends StatelessWidget {
  const _SparkleDivider({required this.starSize});

  final double starSize;

  @override
  Widget build(BuildContext context) {
    final line = RuniacColors.primaryBlue.withValues(alpha: 0.32);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Container(height: 1.5, color: line)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: SizedBox(
            width: starSize,
            height: starSize,
            child: const CustomPaint(painter: _SparkleStarPainter()),
          ),
        ),
        Expanded(child: Container(height: 1.5, color: line)),
      ],
    );
  }
}

class _SparkleStarPainter extends CustomPainter {
  const _SparkleStarPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = RuniacColors.accentOrange
      ..style = PaintingStyle.fill;
    // Four-point sparkle: control points pulled to the center make each side
    // concave, giving the thin twinkle arms.
    final path = Path()
      ..moveTo(cx, 0)
      ..quadraticBezierTo(cx, cy, size.width, cy)
      ..quadraticBezierTo(cx, cy, cx, size.height)
      ..quadraticBezierTo(cx, cy, 0, cy)
      ..quadraticBezierTo(cx, cy, cx, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_SparkleStarPainter oldDelegate) => false;
}

class _RunnerDivider extends StatelessWidget {
  const _RunnerDivider({required this.iconSize});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final near = RuniacColors.primaryBlue.withValues(alpha: 0.42);
    final far = RuniacColors.primaryBlue.withValues(alpha: 0.04);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [far, near]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Icon(
            Icons.directions_run,
            size: iconSize,
            color: RuniacColors.primaryBlue,
          ),
        ),
        Expanded(
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [near, far]),
            ),
          ),
        ),
      ],
    );
  }
}

// Shared card content rendered by both cards: league badge crest, region,
// division, and the large rank number. Positioned with fractional offsets so
// it lines up with the solid card's baked artwork and scales on the
// transparent card.
class _ShareRankCardBody extends StatelessWidget {
  const _ShareRankCardBody({
    required this.regionName,
    required this.divisionName,
    required this.rankLabel,
    required this.leagueBadgeAssetPath,
  });

  final String regionName;
  final String divisionName;
  final String rankLabel;
  final String leagueBadgeAssetPath;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        final cardHeight = constraints.maxHeight;

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: cardWidth * 0.34,
              right: cardWidth * 0.29,
              top: cardHeight * 0.344,
              height: cardHeight * 0.075,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  regionName,
                  maxLines: 1,
                  textAlign: TextAlign.left,
                  style: const TextStyle(
                    color: RuniacColors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    height: 1,
                    shadows: [
                      Shadow(
                        color: Color(0x99000000),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              left: cardWidth * 0.12,
              right: cardWidth * 0.12,
              top: cardHeight * 0.425,
              height: cardHeight * 0.075,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // League badge sits in front of the division name.
                    Image.asset(
                      leagueBadgeAssetPath,
                      key: const Key('leaderboard_share_rank_league_badge'),
                      height: 44,
                      width: 44,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      divisionName,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFE1E8FF),
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        shadows: [
                          Shadow(
                            color: Color(0x99000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: cardWidth * 0.2,
              right: cardWidth * 0.2,
              top: cardHeight * 0.535,
              height: cardHeight * 0.225,
              child: FittedBox(
                fit: BoxFit.contain,
                child: _ShareRankNumber(rankLabel: rankLabel),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ShareRankNumber extends StatelessWidget {
  const _ShareRankNumber({required this.rankLabel});

  final String rankLabel;

  @override
  Widget build(BuildContext context) {
    // Numeric ranks arrive as '#18'; a rank-less runner arrives as the plain
    // backend summary word (e.g. 'Unranked'), which reads wrong with the
    // decorative '#' glyph in front of it.
    final hasRankNumber = rankLabel.startsWith('#');
    final rankNumber = hasRankNumber ? rankLabel.substring(1) : rankLabel;

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (hasRankNumber)
          const Text(
            '#',
            style: TextStyle(
              color: RuniacColors.accentOrange,
              fontSize: 122,
              fontWeight: FontWeight.w900,
              height: 0.94,
              shadows: [
                Shadow(
                  color: Color(0xAA000000),
                  blurRadius: 16,
                  offset: Offset(0, 3),
                ),
              ],
            ),
          ),
        Text(
          rankNumber,
          style: const TextStyle(
            color: RuniacColors.white,
            fontSize: 150,
            fontWeight: FontWeight.w900,
            height: 0.94,
            shadows: [
              Shadow(
                color: Color(0xAA000000),
                blurRadius: 16,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
