import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import 'shared_route_detail_sections.dart';

/// The header and share flow of the shared-route detail screen.
///
/// Sharing shows [RouteDetailSharePreviewSheet] first — the runner sees exactly
/// what will be published before it is, since a route reveals where someone
/// runs. The notice in that sheet is part of the flow, not decoration.
class RouteDetailHeader extends StatelessWidget {
  const RouteDetailHeader({required this.onShare, super.key});

  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 6),
      child: Row(
        children: [
          Semantics(
            label: 'Back',
            button: true,
            child: IconButton(
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_ios_new, size: 22),
              color: RuniacColors.primaryBlue,
            ),
          ),
          const Expanded(
            child: Text(
              'Route',
              style: TextStyle(
                color: RuniacColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Semantics(
            label: 'Share route',
            button: true,
            child: IconButton(
              tooltip: 'Share route',
              onPressed: onShare,
              icon: const Icon(Icons.share_outlined),
              color: RuniacColors.primaryBlue,
            ),
          ),
        ],
      ),
    );
  }
}

class RouteDetailSharePreviewSheet extends StatelessWidget {
  const RouteDetailSharePreviewSheet({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Share route preview',
                style: TextStyle(
                  color: RuniacColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              const _RouteShareSummaryCard(),
              const SizedBox(height: 14),
              const _SharePreviewNotice(),
              const SizedBox(height: 16),
              const _SharePreviewActionRow(
                icon: Icons.link,
                label: 'Copy Link',
              ),
              const SizedBox(height: 8),
              const _SharePreviewActionRow(
                icon: Icons.chat_bubble_outline,
                label: 'Messages',
              ),
              const SizedBox(height: 8),
              const _SharePreviewActionRow(
                icon: Icons.more_horiz,
                label: 'More',
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: onClose,
                style: RuniacButtonStyles.primary(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RouteShareSummaryCard extends StatelessWidget {
  const _RouteShareSummaryCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RuniacColors.white,
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFF),
              border: Border.all(color: RuniacColors.border),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.route_outlined,
              color: RuniacColors.primaryBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  routeDetailTitle,
                  style: TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  '3.2 km · 25 min · Easy',
                  style: TextStyle(
                    color: RuniacColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7F2),
              border: Border.all(color: Color(0xFFFFE2D4)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Preview only',
              style: TextStyle(
                color: RuniacColors.accentOrange,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharePreviewNotice extends StatelessWidget {
  const _SharePreviewNotice();

  @override
  Widget build(BuildContext context) {
    const noticeStyle = TextStyle(
      color: RuniacColors.textSecondary,
      fontSize: 14,
      height: 1.4,
    );
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Route sharing is preview-only in this prototype.',
          style: noticeStyle,
        ),
        SizedBox(height: 4),
        Text('Link sharing will be available after setup.', style: noticeStyle),
      ],
    );
  }
}

class _SharePreviewActionRow extends StatelessWidget {
  const _SharePreviewActionRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: RuniacColors.border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: RuniacColors.textSecondary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: RuniacColors.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Text(
            'Coming soon',
            style: TextStyle(
              color: RuniacColors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class RouteDetailBottomActionBar extends StatelessWidget {
  const RouteDetailBottomActionBar({
    required this.isBookmarked,
    required this.onBookmark,
    required this.onSelectRoute,
    super.key,
  });

  final bool isBookmarked;
  final VoidCallback onBookmark;
  final VoidCallback? onSelectRoute;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RuniacColors.white,
        border: Border(top: BorderSide(color: RuniacColors.border)),
        boxShadow: [
          BoxShadow(
            color: Color(0x10172033),
            blurRadius: 16,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              SizedBox(
                width: 60,
                height: 56,
                child: Semantics(
                  label: 'Save route',
                  button: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: RuniacColors.white,
                      border: Border.all(color: RuniacColors.border),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: IconButton(
                      tooltip: 'Save route',
                      onPressed: onBookmark,
                      color: RuniacColors.primaryBlue,
                      icon: Icon(
                        isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                        size: 29,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onSelectRoute,
                  style: RuniacButtonStyles.primary(
                    disabledBackgroundColor:
                        RuniacColors.disabledButtonBackground,
                    disabledForegroundColor:
                        RuniacColors.disabledButtonForeground,
                    minimumSize: const Size.fromHeight(56),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text(
                    'Select Route',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RouteDetailSavingOverlay extends StatelessWidget {
  const RouteDetailSavingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x8A0F172A),
        child: Center(
          child: Container(
            width: 250,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: RuniacColors.white,
              border: Border.all(color: RuniacColors.border),
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1F172033),
                  blurRadius: 22,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: RuniacColors.primaryBlue),
                SizedBox(height: 18),
                Text(
                  'Setting up your next run...',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: RuniacColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
