part of 'home_stage_map.dart';

class _LoadingProfileBadge extends StatelessWidget {
  const _LoadingProfileBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Runner profile loading',
      child: Container(
        width: 54,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: RuniacColors.primaryBlue.withValues(alpha: 0.24),
          shape: BoxShape.circle,
          border: Border.all(color: RuniacColors.white, width: 2),
        ),
        child: const Text(
          '…',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            height: 1,
          ),
        ),
      ),
    );
  }
}

BoxDecoration _homeStageControlDecoration({
  BorderRadius? borderRadius,
  BoxShape shape = BoxShape.rectangle,
  double fillAlpha = 0.92,
}) {
  return BoxDecoration(
    color: RuniacColors.textPrimary.withValues(alpha: fillAlpha),
    borderRadius: borderRadius,
    shape: shape,
    border: Border.all(color: RuniacColors.white.withValues(alpha: 0.42)),
    boxShadow: [
      BoxShadow(
        color: RuniacColors.textPrimary.withValues(alpha: 0.42),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ],
  );
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final label = count > 99 ? '99+' : '$count';
    return Container(
      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFDC2626),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
