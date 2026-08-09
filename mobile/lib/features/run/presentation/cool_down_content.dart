part of 'cool_down_guide_screen.dart';

class _CoolDownStepIdentity extends StatelessWidget {
  const _CoolDownStepIdentity({
    required this.icon,
    required this.title,
    required this.helper,
    required this.compact,
  });

  final IconData icon;
  final String title;
  final String helper;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 28 : 30,
              height: compact ? 28 : 30,
              decoration: BoxDecoration(
                color: _navy06,
                border: Border.all(color: _navy10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _navy, size: compact ? 17 : 19),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _navy,
                  fontSize: compact ? 20 : 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            helper,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _navy60,
              fontSize: compact ? 13 : 14,
              fontWeight: FontWeight.w500,
              height: 1.48,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _CoolDownTipsCard extends StatelessWidget {
  const _CoolDownTipsCard({required this.tips, required this.compact});

  final List<String> tips;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return _SoftCard(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 9 : 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 24 : 28,
                height: compact ? 24 : 28,
                decoration: BoxDecoration(
                  color: _pureWhite,
                  border: Border.all(color: _navy10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: _navy,
                  size: 15,
                ),
              ),
              const SizedBox(width: 9),
              const Text(
                'Tips',
                style: TextStyle(
                  color: _navy,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 6 : 11),
          for (final tip in tips) ...[
            _TipRow(tip: tip, compact: compact),
            if (tip != tips.last) SizedBox(height: compact ? 5 : 9),
          ],
        ],
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  const _TipRow({required this.tip, required this.compact});

  final String tip;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: compact ? 18 : 22,
          height: compact ? 18 : 22,
          decoration: BoxDecoration(
            color: _navy06,
            border: Border.all(color: _navy10),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            color: _navy60,
            size: compact ? 11 : 13,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            tip,
            style: TextStyle(
              color: _navy75,
              fontSize: compact ? 12.5 : 13,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
