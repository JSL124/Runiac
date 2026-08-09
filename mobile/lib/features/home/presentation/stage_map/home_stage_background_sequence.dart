import 'dart:ui' show Offset;

/// Full-bleed cartoon Singapore backgrounds used for the Home stage map.
///
/// Every asset is a 941:1672 scene with a winding path receding from the
/// bottom foreground toward the top. One background is assigned per plan week.
const List<String> kHomeStageBackgroundAssets = <String>[
  'assets/images/home/backgrounds/bg_gardens_by_the_bay.webp',
  'assets/images/home/backgrounds/bg_east_coast_beach.webp',
  'assets/images/home/backgrounds/bg_kampong_glam.webp',
  'assets/images/home/backgrounds/bg_clarke_quay_night.webp',
  'assets/images/home/backgrounds/bg_supertree_grove.webp',
  'assets/images/home/backgrounds/bg_marina_bay_sunset.webp',
  'assets/images/home/backgrounds/bg_jewel_waterfall.webp',
  'assets/images/home/backgrounds/bg_palawan_sunset.webp',
];

/// Aspect ratio (height / width) of every background asset (1672 / 941).
const double kHomeStageBackgroundAspect = 1672 / 941;

List<double> _uniformAnchorDys({required double bottom, required double top}) {
  return <double>[
    for (var index = 0; index < 7; index++) bottom - (bottom - top) * index / 6,
  ];
}

/// The first/bottom background lifts day 1 above the bottom navigation.
final List<double> _kFirstSectionAnchorDys = _uniformAnchorDys(
  bottom: 0.86,
  top: 0.19,
);

/// Later backgrounds can use their full height. With the 8% section overlap,
/// the 0.97 -> 0.19 span also makes the cross-background gap approximately
/// equal to the within-background interval.
final List<double> _kContinuingSectionAnchorDys = _uniformAnchorDys(
  bottom: 0.97,
  top: 0.19,
);

List<Offset> _anchorsFromDx(List<double> dxValues, List<double> dyValues) {
  return [
    for (var i = 0; i < dxValues.length; i++) Offset(dxValues[i], dyValues[i]),
  ];
}

/// Seven anchors that draw a `<` across one complete background.
///
/// Both ends meet at the horizontal centre so the path connects cleanly to
/// the next background. The middle day forms the left-facing point.
const List<double> _kLeftChevronDx = <double>[
  0.50,
  0.43,
  0.35,
  0.27,
  0.35,
  0.43,
  0.50,
];

/// Seven anchors that draw a `>` across one complete background.
const List<double> _kRightChevronDx = <double>[
  0.50,
  0.57,
  0.65,
  0.73,
  0.65,
  0.57,
  0.50,
];

/// Normalized 7-point anchors for a vertically stacked background section.
///
/// Even sections draw `<`, odd sections draw `>`, and every section begins
/// and ends at x=0.5. The result is one connected `< > < >` stage path across
/// the full scrolling map regardless of the randomized background assets.
List<Offset> homeStageAnchorsForSection(int sectionIndex) {
  final dyValues = sectionIndex == 0
      ? _kFirstSectionAnchorDys
      : _kContinuingSectionAnchorDys;
  return _anchorsFromDx(
    sectionIndex.isEven ? _kLeftChevronDx : _kRightChevronDx,
    dyValues,
  );
}

/// Stable 32-bit FNV-1a hash over the UTF-16 code units of [input].
///
/// Used instead of [String.hashCode] because the latter is not guaranteed to
/// be stable across Dart runtimes/sessions. This function is a pure, stable
/// mapping so a given plan id always yields the same background ordering.
int stableFnv1aHash(String input) {
  const int fnvOffsetBasis = 0x811c9dc5;
  const int fnvPrime = 0x01000193;
  var hash = fnvOffsetBasis;
  for (var i = 0; i < input.length; i++) {
    hash ^= input.codeUnitAt(i);
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash;
}

/// Deterministic background ordering for a plan.
///
/// The sequence is derived only from [planId] (via [stableFnv1aHash] seeding a
/// small LCG), so the same plan id yields an identical sequence every session
/// with no persistence. A chosen background never equals either of the two
/// backgrounds used immediately before it, avoiding visible repeats.
List<String> homeStageBackgroundSequence({
  required String planId,
  required int weekCount,
  List<String> palette = kHomeStageBackgroundAssets,
}) {
  if (weekCount <= 0 || palette.isEmpty) {
    return const <String>[];
  }
  if (palette.length == 1) {
    return List<String>.filled(weekCount, palette.first);
  }

  var state = stableFnv1aHash('runiac-stage-bg::$planId');
  int nextRandom() {
    // Numerical Recipes LCG constants; keeps values within 32 bits.
    state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;
    return state;
  }

  final result = <String>[];
  String? previous;
  String? beforePrevious;
  for (var week = 0; week < weekCount; week++) {
    final candidates = <String>[
      for (final option in palette)
        if (option != previous && option != beforePrevious) option,
    ];
    // With a palette of 3+ entries the exclusion of the last two used
    // backgrounds always leaves at least one candidate.
    final pool = candidates.isEmpty ? palette : candidates;
    final choice = pool[nextRandom() % pool.length];
    result.add(choice);
    beforePrevious = previous;
    previous = choice;
  }
  return result;
}
