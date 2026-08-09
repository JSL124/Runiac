part of 'cool_down_guide_screen.dart';

class _CoolDownUpNextCard extends StatelessWidget {
  const _CoolDownUpNextCard();

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _pureWhite,
              border: Border.all(color: _navy10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.self_improvement_rounded,
              color: _navy,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UP NEXT',
                  style: TextStyle(
                    color: _navy45,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Gentle Stretch',
                  style: TextStyle(
                    color: _navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '~${(stretchTotalSeconds / 60).ceil()} min · gentle recovery',
                  style: const TextStyle(
                    color: _navy60,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SoftCard extends StatelessWidget {
  const _SoftCard({required this.child, required this.padding});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _navy06,
        border: Border.all(color: _navy10),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
