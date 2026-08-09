part of 'cool_down_guide_screen.dart';

class _CoolDownPauseButton extends StatelessWidget {
  const _CoolDownPauseButton({required this.status, required this.onPressed});

  final _CoolDownStatus status;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final paused = status == _CoolDownStatus.paused;

    return IconButton(
      tooltip: paused ? 'Resume' : 'Pause',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: _navy,
        foregroundColor: _pureWhite,
        fixedSize: const Size(58, 58),
        shape: const CircleBorder(),
        elevation: 8,
        shadowColor: const Color(0x332F51C8),
      ),
      icon: Icon(
        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        size: 28,
      ),
    );
  }
}

enum _CtaTone { navy, orange }

class _CoolDownPrimaryCta extends StatelessWidget {
  const _CoolDownPrimaryCta({
    required this.label,
    required this.tone,
    required this.onPressed,
  });

  final String label;
  final _CtaTone tone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = tone == _CtaTone.orange ? _orange : _navy;
    final shadowColor = tone == _CtaTone.orange
        ? const Color(0x42FB6414)
        : const Color(0x332F51C8);

    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: _pureWhite,
        minimumSize: const Size.fromHeight(56),
        elevation: 8,
        shadowColor: shadowColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
  }
}
