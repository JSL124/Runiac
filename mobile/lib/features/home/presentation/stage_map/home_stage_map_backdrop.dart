part of 'home_stage_map.dart';

class _FadingBackground extends StatelessWidget {
  const _FadingBackground({required this.asset});

  final String asset;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (rect) {
        return const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white],
          stops: [0.0, _kFadeFraction],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) =>
            const ColoredBox(color: Color(0xFFBFE3F5)),
      ),
    );
  }
}
