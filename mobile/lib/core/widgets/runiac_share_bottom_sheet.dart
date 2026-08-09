import 'package:flutter/material.dart';

import 'runiac_bottom_sheet_handle.dart';

const _blue = Color(0xFF2F51C8);
const _surface = Color(0xFFF4F7FF);
const _card = Color(0xFFFFFFFF);
const _ink = Color(0xFF16235C);
const _blue75 = Color(0xBF2F51C8);
const _blue60 = Color(0x992F51C8);
const _blue18 = Color(0x2E2F51C8);
const _blue10 = Color(0x1A2F51C8);

/// The shared sheet used everywhere Runiac offers to share something — a run,
/// an achievement, a route.
///
/// It only presents the targets and reports which was chosen; it never builds
/// the shared artefact itself. Each caller passes in what it wants shared,
/// which is why a share card and a route link can use the same sheet.
class RuniacShareBottomSheet extends StatelessWidget {
  const RuniacShareBottomSheet({
    super.key,
    required this.title,
    required this.preview,
    required this.shareTargets,
    this.leadingActionLabel = 'Close',
    this.onLeadingAction,
    this.actionRow,
    this.subtitle,
    this.heightFactor = 0.82,
    this.contentPadding,
  });

  final String title;
  final Widget preview;
  final List<Widget> shareTargets;
  final String leadingActionLabel;
  final VoidCallback? onLeadingAction;
  final Widget? actionRow;
  final String? subtitle;
  final double heightFactor;
  final EdgeInsets? contentPadding;

  @override
  Widget build(BuildContext context) {
    final sheetHeight = MediaQuery.sizeOf(context).height * heightFactor;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final padding =
        contentPadding ?? EdgeInsets.fromLTRB(20, 9, 20, 12 + bottomInset);

    return SizedBox(
      height: sheetHeight,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Color(0x292F51C8),
              blurRadius: 50,
              offset: Offset(0, -18),
            ),
          ],
        ),
        child: Padding(
          padding: padding,
          child: Column(
            children: [
              const Center(
                child: RuniacBottomSheetHandle(
                  width: 40,
                  height: 5,
                  color: _blue18,
                  borderRadius: 99,
                ),
              ),
              _RuniacShareSheetHeader(
                title: title,
                subtitle: subtitle,
                leadingActionLabel: leadingActionLabel,
                onLeadingAction:
                    onLeadingAction ?? () => Navigator.of(context).pop(),
              ),
              Flexible(
                child: Align(alignment: Alignment.topCenter, child: preview),
              ),
              if (actionRow != null) ...[
                const SizedBox(height: 10),
                actionRow!,
              ],
              const SizedBox(height: 12),
              DecoratedBox(
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: _blue10)),
                ),
                child: Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: RuniacShareTargetRow(targets: shareTargets),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RuniacShareSheetHeader extends StatelessWidget {
  const _RuniacShareSheetHeader({
    required this.title,
    required this.leadingActionLabel,
    required this.onLeadingAction,
    this.subtitle,
  });

  final String title;
  final String leadingActionLabel;
  final VoidCallback onLeadingAction;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
      child: SizedBox(
        height: subtitle == null ? 36 : 54,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onLeadingAction,
                style: TextButton.styleFrom(
                  foregroundColor: _blue,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  minimumSize: const Size(48, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
                child: Text(leadingActionLabel),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 58),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _blue60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RuniacShareTargetRow extends StatelessWidget {
  const RuniacShareTargetRow({super.key, required this.targets});

  final List<Widget> targets;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SHARE TO',
          style: TextStyle(
            color: _blue60,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: targets,
        ),
      ],
    );
  }
}

class RuniacShareTargetButton extends StatefulWidget {
  const RuniacShareTargetButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.iconAsset,
    this.enabled = true,
  });

  final IconData icon;
  final String? iconAsset;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;

  @override
  State<RuniacShareTargetButton> createState() =>
      _RuniacShareTargetButtonState();
}

class _RuniacShareTargetButtonState extends State<RuniacShareTargetButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled || _pressed == value) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    const actionWidth = 61.0;
    const iconBoxSize = 56.0;
    const iconVisualSize = 22.0;
    const assetIconVisualSize = 26.0;
    const labelGap = 6.0;
    const labelAreaHeight = 30.0;
    final enabled = widget.enabled;
    final foreground = enabled ? _blue : _blue75.withValues(alpha: 0.45);
    final pressed = _pressed && enabled;

    return SizedBox(
      width: actionWidth,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: widget.label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: enabled ? (_) => _setPressed(true) : null,
          onTapUp: enabled ? (_) => _setPressed(false) : null,
          onTapCancel: () => _setPressed(false),
          onTap: enabled ? widget.onPressed : null,
          child: AnimatedScale(
            scale: pressed ? 0.88 : 1.0,
            duration: const Duration(milliseconds: 90),
            curve: Curves.easeOut,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 90),
                  width: iconBoxSize,
                  height: iconBoxSize,
                  decoration: BoxDecoration(
                    color: pressed ? _blue18 : _card,
                    border: Border.all(color: pressed ? _blue : _blue10),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x142F51C8),
                        blurRadius: 14,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: widget.iconAsset == null
                      ? Icon(
                          widget.icon,
                          color: foreground,
                          size: iconVisualSize,
                        )
                      : Image.asset(
                          widget.iconAsset!,
                          width: assetIconVisualSize,
                          height: assetIconVisualSize,
                          fit: BoxFit.contain,
                        ),
                ),
                const SizedBox(height: labelGap),
                SizedBox(
                  height: labelAreaHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      widget.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: enabled
                            ? _blue75
                            : _blue75.withValues(alpha: 0.45),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0,
                        height: 1.18,
                      ),
                    ),
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
