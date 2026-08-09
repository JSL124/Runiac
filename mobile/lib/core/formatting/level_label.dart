/// Shared backend-owned level label formatting.
///
/// The backend already formats the trusted level label (e.g. `'Level 12'` or
/// `'Lv.12'`); the client only compacts it for presentation and never derives
/// a level from anything. Any row-style badge that needs the compact `Lv.N`
/// form (Friends, Feed authors/comments, challenge rosters, etc.) should
/// route its backend-supplied label through this helper rather than
/// re-implementing the transform.
String compactLevelLabel(String levelLabel) {
  final trimmed = levelLabel.trim();
  if (trimmed.isEmpty) return '';
  final match = RegExp(
    r'^Level\s+(.+)$',
    caseSensitive: false,
  ).firstMatch(trimmed);
  return match == null ? trimmed : 'Lv.${match.group(1)!.trim()}';
}
