part of 'run_launch_screen.dart';

class _RunBottomSheetShell extends StatelessWidget {
  const _RunBottomSheetShell({
    super.key,
    required this.bottomInset,
    required this.mode,
    required this.extent,
    required this.sheetProgress,
    required this.onHandleTap,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onVerticalDragCancel,
    required this.child,
  });

  final double bottomInset;
  final RunSheetMode mode;
  final RunLaunchSheetExtent extent;
  final double sheetProgress;
  final VoidCallback onHandleTap;
  final GestureDragStartCallback onVerticalDragStart;
  final GestureDragUpdateCallback onVerticalDragUpdate;
  final GestureDragEndCallback onVerticalDragEnd;
  final GestureDragCancelCallback onVerticalDragCancel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final collapsed = extent == RunLaunchSheetExtent.collapsed;
        final contentVisible = sheetProgress > 0.01;
        final horizontalPadding = mode == RunSheetMode.preRun
            ? (compact ? 22.0 : 28.0)
            : 24.0;
        const topPadding = 0.0;
        final bottomPadding =
            bottomInset +
            (collapsed
                ? 0.0
                : mode == RunSheetMode.preRun
                ? (compact ? 18.0 : 22.0)
                : (compact ? 18.0 : 22.0));

        return Container(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            bottomPadding,
          ),
          decoration: BoxDecoration(
            color: RuniacColors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26172033),
                blurRadius: 26,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                key: const Key('runLaunchSheetHandleArea'),
                behavior: HitTestBehavior.opaque,
                onTap: onHandleTap,
                onVerticalDragStart: onVerticalDragStart,
                onVerticalDragUpdate: onVerticalDragUpdate,
                onVerticalDragEnd: onVerticalDragEnd,
                onVerticalDragCancel: onVerticalDragCancel,
                child: const SizedBox(
                  height: _collapsedRunSheetHeight,
                  child: Center(
                    child: RuniacBottomSheetHandle(
                      key: Key('runLaunchSheetHandle'),
                      semanticLabel: 'Run launch sheet handle',
                    ),
                  ),
                ),
              ),
              if (collapsed) ...[
                const SizedBox.shrink(
                  key: Key('runLaunchSheetCollapsedContent'),
                ),
              ],
              Offstage(offstage: collapsed || !contentVisible, child: child),
            ],
          ),
        );
      },
    );
  }
}
