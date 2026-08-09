part of 'view_summary_screen.dart';

class _AnalysisSection extends StatelessWidget {
  const _AnalysisSection({
    required this.hasSufficientData,
    required this.paceAnalysis,
    required this.onMoreDetails,
  });

  final bool hasSufficientData;
  final AdvancedAnalysisPaceAnalysis paceAnalysis;
  final VoidCallback onMoreDetails;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SectionLabel(title: 'Splits'),
          const _AnalysisDivider(),
          const SizedBox(height: 14),
          _GuardedAnalysisPreview(
            showGuard: !hasSufficientData,
            clipContent: false,
            minHeight: hasSufficientData ? 0 : 96,
            child: AdvancedAnalysisSplitTable(analysis: paceAnalysis),
          ),
          const SizedBox(height: 12),
          const _AnalysisDivider(),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: onMoreDetails,
            style: OutlinedButton.styleFrom(
              foregroundColor: _rBlue,
              side: const BorderSide(color: _rBlue18, width: 1.5),
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            child: const Text('More Details'),
          ),
        ],
      ),
    );
  }
}

class _AnalysisDivider extends StatelessWidget {
  const _AnalysisDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: _rBlue10, height: 17, thickness: 1);
  }
}

class _GuardedAnalysisPreview extends StatelessWidget {
  const _GuardedAnalysisPreview({
    required this.showGuard,
    required this.child,
    this.clipContent = true,
    this.minHeight = 0,
  });

  final bool showGuard;
  final Widget child;
  final bool clipContent;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final preview = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          child,
          if (showGuard) const Positioned.fill(child: _LowDataGraphGuard()),
        ],
      ),
    );
    if (!clipContent) {
      return preview;
    }
    return ClipRRect(borderRadius: BorderRadius.circular(14), child: preview);
  }
}

class _LowDataGraphGuard extends StatelessWidget {
  const _LowDataGraphGuard();

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 3.2, sigmaY: 3.2),
        child: DecoratedBox(
          decoration: BoxDecoration(color: _rWhite.withValues(alpha: 0.44)),
          child: Center(
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'More run data needed',
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _rOrange,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      shadows: [
                        Shadow(color: _rWhite, blurRadius: 10),
                        Shadow(
                          color: _rWhite,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 3),
                  Text(
                    'Pace insights will appear after a longer run.',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _rOrange,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      shadows: [
                        Shadow(color: _rWhite, blurRadius: 10),
                        Shadow(
                          color: _rWhite,
                          blurRadius: 2,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
