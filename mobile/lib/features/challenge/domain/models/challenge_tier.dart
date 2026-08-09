import 'challenge_enums.dart';
import 'challenge_parse.dart';
import 'challenge_parse_exception.dart';

/// Immutable mirror of one server-owned catalog tier (`challenge-distance-v1`).
///
/// The nine tiers are backend constants. The client renders them and never
/// invents a target, minimum, or duration.
class ChallengeTier {
  const ChallengeTier({
    required this.tierId,
    required this.catalogVersion,
    required this.difficultyLabel,
    required this.durationDays,
    required this.maxParticipants,
    required this.maxInvitedFriends,
    required this.targetMeters,
    required this.personalMinimumMeters,
  });

  final ChallengeTierId tierId;
  final String catalogVersion;
  final String difficultyLabel;
  final int durationDays;
  final int maxParticipants;
  final int maxInvitedFriends;

  /// The solo full-distance target in integer metres.
  final int targetMeters;

  /// The per-member group personal minimum in integer metres.
  final int personalMinimumMeters;

  /// Parses one entry from the `getChallengeCatalog` callable, which exposes the
  /// tier target as `soloTargetMeters`. [catalogVersion] is threaded from the
  /// enclosing catalog envelope.
  static ChallengeTier fromCatalogEntry(
    Map<String, Object?> map, {
    required String catalogVersion,
  }) {
    return ChallengeTier(
      tierId: ChallengeTierId.parse(ChallengeParse.string(map, 'tierId')),
      catalogVersion: catalogVersion,
      difficultyLabel: ChallengeParse.string(map, 'difficultyLabel'),
      durationDays: ChallengeParse.integer(map, 'durationDays'),
      maxParticipants: ChallengeParse.integer(map, 'maxParticipants'),
      maxInvitedFriends: ChallengeParse.integer(map, 'maxInvitedFriends'),
      targetMeters: ChallengeParse.integer(map, 'soloTargetMeters'),
      personalMinimumMeters:
          ChallengeParse.integer(map, 'personalMinimumMeters'),
    );
  }
}

/// The versioned catalog envelope returned by `getChallengeCatalog`.
class ChallengeCatalog {
  const ChallengeCatalog({
    required this.version,
    required this.tiers,
    this.premiumOnlyTierIds = const <ChallengeTierId>{},
  });

  final String version;
  final List<ChallengeTier> tiers;

  /// Tiers the backend gates behind Premium for NEW lobby creation
  /// (`config/challengeAccess.premiumOnlyTiers`, relayed as an additive
  /// catalog field). This drives display-only lock UI: the real gate is
  /// `createChallengeLobby` throwing `PREMIUM_REQUIRED` server-side, so an
  /// absent or malformed field parses to empty (fail-open) rather than
  /// failing the whole catalog.
  final Set<ChallengeTierId> premiumOnlyTierIds;

  bool isPremiumOnly(ChallengeTierId tierId) =>
      premiumOnlyTierIds.contains(tierId);

  static ChallengeCatalog fromMap(Map<String, Object?> map) {
    final version = ChallengeParse.string(map, 'version');
    final rawTiers = ChallengeParse.asList(map['tiers'], field: 'tiers');
    final tiers = rawTiers
        .map(
          (entry) => ChallengeTier.fromCatalogEntry(
            ChallengeParse.asMap(entry, field: 'tiers[]'),
            catalogVersion: version,
          ),
        )
        .toList(growable: false);
    return ChallengeCatalog(
      version: version,
      tiers: List<ChallengeTier>.unmodifiable(tiers),
      premiumOnlyTierIds: _parsePremiumOnlyTiers(map['premiumOnlyTiers']),
    );
  }

  /// Lenient by design, unlike the strict tier parsing above: the field is
  /// additive and admin-configurable, so a server gating a tier id this client
  /// version does not know must not break the catalog. Unknown or non-string
  /// entries are skipped; a missing or non-list value yields the empty set.
  static Set<ChallengeTierId> _parsePremiumOnlyTiers(Object? raw) {
    if (raw is! List) {
      return const <ChallengeTierId>{};
    }
    final tierIds = <ChallengeTierId>{};
    for (final entry in raw) {
      if (entry is! String) {
        continue;
      }
      try {
        tierIds.add(ChallengeTierId.parse(entry));
      } on ChallengeParseException {
        // Skip: additive contract — never fail the catalog over it.
      }
    }
    return Set<ChallengeTierId>.unmodifiable(tierIds);
  }
}
