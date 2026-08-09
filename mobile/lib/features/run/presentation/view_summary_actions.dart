part of 'view_summary_screen.dart';

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.hasSufficientData,
    required this.showXpUpdateAction,
    required this.showLowDataSaveAction,
    required this.onShareRoute,
    required this.onXpUpdate,
    required this.onGoHome,
  });

  final bool hasSufficientData;
  final bool showXpUpdateAction;
  final bool showLowDataSaveAction;
  final VoidCallback onShareRoute;
  final VoidCallback onXpUpdate;
  final VoidCallback onGoHome;

  @override
  Widget build(BuildContext context) {
    if (!hasSufficientData && !showLowDataSaveAction) {
      return const SizedBox.shrink();
    }

    if (!hasSufficientData) {
      return _BottomActionBar(
        child: FilledButton.icon(
          onPressed: onGoHome,
          icon: const Icon(Icons.home_rounded, size: 19),
          label: const Text('Go to Home'),
          style: FilledButton.styleFrom(
            backgroundColor: _rBlue,
            foregroundColor: _rWhite,
            minimumSize: const Size.fromHeight(56),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
            elevation: 8,
            shadowColor: const Color(0x382F51C8),
          ),
        ),
      );
    }

    return _BottomActionBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton.icon(
            onPressed: onShareRoute,
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text('Share Route'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _rBlue,
              side: const BorderSide(color: _rBlue30, width: 1.5),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (showXpUpdateAction) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onXpUpdate,
              icon: const Icon(Icons.auto_awesome_rounded, size: 19),
              label: const Text('View XP Update'),
              style: FilledButton.styleFrom(
                backgroundColor: _rOrange,
                foregroundColor: _rWhite,
                minimumSize: const Size.fromHeight(56),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
                elevation: 8,
                shadowColor: const Color(0x4DFB6414),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 26),
      decoration: const BoxDecoration(
        color: _rWhite,
        border: Border(top: BorderSide(color: _rBlue10)),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: const TextStyle(
          color: _rBlue,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
    );
  }
}

class _CardSurface extends StatelessWidget {
  const _CardSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _rWhite,
        border: Border.all(color: RuniacColors.cardBorder),
        borderRadius: BorderRadius.circular(_cardRadius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
