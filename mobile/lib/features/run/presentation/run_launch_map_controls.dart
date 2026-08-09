part of 'run_launch_screen.dart';

class _MapCircleButton extends StatefulWidget {
  const _MapCircleButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_MapCircleButton> createState() => _MapCircleButtonState();
}

class _MapCircleButtonState extends State<_MapCircleButton> {
  bool _pressed = false;
  bool _activating = false;

  bool get _visuallyPressed => _pressed || _activating;

  void _setPressed(bool pressed) {
    if (!mounted || _pressed == pressed) {
      return;
    }
    setState(() => _pressed = pressed);
  }

  Future<void> _handleTap() async {
    setState(() => _activating = true);
    await Future<void>.delayed(_controlPressHold);
    if (!mounted) {
      return;
    }
    setState(() {
      _activating = false;
      _pressed = false;
    });
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: AnimatedScale(
        scale: _visuallyPressed ? 0.94 : 1,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutCubic,
        child: Material(
          color: _visuallyPressed ? const Color(0xFFE8EEFF) : Colors.white,
          elevation: 8,
          shadowColor: const Color(0x33172033),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkResponse(
            onTap: _handleTap,
            onHighlightChanged: _setPressed,
            containedInkWell: true,
            customBorder: const CircleBorder(),
            radius: 34,
            splashColor: const Color(0x1A3151C8),
            highlightColor: const Color(0x143151C8),
            child: SizedBox(
              width: 58,
              height: 58,
              child: Icon(widget.icon, color: _panelTextBlue, size: 30),
            ),
          ),
        ),
      ),
    );
  }
}
