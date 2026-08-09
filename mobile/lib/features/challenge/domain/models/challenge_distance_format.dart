/// Display-only distance formatting for Challenge surfaces.
///
/// DISPLAY ONLY. Eligibility, targets, personal minimums, and team progress are
/// always compared and stored as integer metres owned by the backend. These
/// helpers round metres to a one-decimal kilometre label purely for rendering;
/// nothing here participates in eligibility, contribution, or reward decisions,
/// and no caller should re-derive a metre value from a formatted string.
abstract final class ChallengeDistanceFormat {
  /// Formats integer metres as a `62.4 km` label (one decimal place).
  ///
  /// The rounding is presentational; the underlying integer metres are never
  /// mutated. `62_400` renders as `62.4 km`.
  static String kilometresLabel(int metres) {
    return '${_kilometres(metres)} km';
  }

  /// Formats a team-progress pair as `X.X / Y.Y km` for the progress ring.
  static String teamProgressLabel({
    required int teamMetres,
    required int targetMetres,
  }) {
    return '${_kilometres(teamMetres)} / ${_kilometres(targetMetres)} km';
  }

  static String _kilometres(int metres) {
    return (metres / 1000).toStringAsFixed(1);
  }
}
