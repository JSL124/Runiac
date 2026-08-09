import 'challenge_enums.dart';
import 'challenge_parse.dart';
import 'challenge_parse_exception.dart';

/// The set of Challenge tier badges a user owns
/// (`users/{uid}/challengeBadges/{tierId}`).
///
/// One ownership doc exists per tier regardless of repeat successes, so this is
/// modelled as a set of owned tier ids. The client only reads ownership; it
/// never grants a badge.
class ChallengeBadgeOwnership {
  ChallengeBadgeOwnership({required Set<ChallengeTierId> ownedTierIds})
      : ownedTierIds = Set<ChallengeTierId>.unmodifiable(ownedTierIds);

  final Set<ChallengeTierId> ownedTierIds;

  bool isOwned(ChallengeTierId tierId) => ownedTierIds.contains(tierId);

  bool get isEmpty => ownedTierIds.isEmpty;

  static final ChallengeBadgeOwnership empty =
      ChallengeBadgeOwnership(ownedTierIds: <ChallengeTierId>{});

  /// Parses a list of owned tier id wire strings (e.g. the ids of the
  /// `challengeBadges` docs). Each id is validated through the tier enum.
  static ChallengeBadgeOwnership fromTierIds(List<Object?> rawTierIds) {
    final owned = <ChallengeTierId>{};
    for (final raw in rawTierIds) {
      if (raw is! String) {
        throw const ChallengeParseException(
          'expected_tier_id_string',
          field: 'challengeBadges[]',
        );
      }
      owned.add(ChallengeTierId.parse(raw));
    }
    return ChallengeBadgeOwnership(ownedTierIds: owned);
  }

  /// Parses a list of `challengeBadges` document maps, each carrying a `tierId`.
  static ChallengeBadgeOwnership fromDocs(List<Object?> rawDocs) {
    final owned = <ChallengeTierId>{};
    for (final raw in rawDocs) {
      final map = ChallengeParse.asMap(raw, field: 'challengeBadges[]');
      owned.add(ChallengeTierId.parse(ChallengeParse.string(map, 'tierId')));
    }
    return ChallengeBadgeOwnership(ownedTierIds: owned);
  }
}
