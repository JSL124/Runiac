part of 'xp_update_screen.dart';

class _XpHeader extends StatelessWidget {
  const _XpHeader({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back to summary',
              onPressed: onBack,
              style: IconButton.styleFrom(
                foregroundColor: _blue45,
                minimumSize: const Size(40, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.chevron_left_rounded, size: 30),
            ),
            const Expanded(
              child: Text(
                'XP & Streak Update',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _blue,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 40),
          ],
        ),
      ),
    );
  }
}
