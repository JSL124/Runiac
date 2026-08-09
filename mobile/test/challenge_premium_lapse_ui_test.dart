import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/challenge/domain/challenge_copy.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_enums.dart';
import 'package:runiac_app/features/challenge/domain/models/challenge_premium_hold.dart';
import 'package:runiac_app/features/challenge/presentation/widgets/challenge_premium_lapse_banner.dart';

// The grace window the server opens on a lapse. The client never computes it —
// it renders the deadline the callable relayed.
final _now = DateTime.fromMillisecondsSinceEpoch(1000000000000);

ChallengePremiumHold _holdIn(Duration remaining) {
  return ChallengePremiumHold(
    graceExpiresAtMs: _now.add(remaining).millisecondsSinceEpoch,
  );
}

void main() {
  group('ChallengePremiumHold', () {
    test('parses the relayed grace deadline', () {
      final hold = ChallengePremiumHold.fromMap(<String, Object?>{
        'graceExpiresAtMs': 1700000000000,
      });

      expect(hold, isNotNull);
      expect(hold!.graceExpiresAtMs, 1700000000000);
      expect(
        hold.graceExpiresAt,
        DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
    });

    test('is null when the caller has no hold', () {
      expect(ChallengePremiumHold.fromMap(null), isNull);
    });

    test('is null rather than throwing on a malformed payload', () {
      // A relay that cannot be understood must degrade to "no warning", never
      // break the whole active-challenge screen.
      expect(ChallengePremiumHold.fromMap(<String, Object?>{}), isNull);
      expect(ChallengePremiumHold.fromMap('nonsense'), isNull);
      expect(
        ChallengePremiumHold.fromMap(<String, Object?>{'graceExpiresAtMs': 'x'}),
        isNull,
      );
    });

    test('reports the remaining window, clamped at zero', () {
      expect(_holdIn(const Duration(hours: 6)).remaining(_now),
          const Duration(hours: 6));
      expect(_holdIn(const Duration(hours: -3)).remaining(_now), Duration.zero);
      expect(_holdIn(const Duration(hours: -3)).hasExpired(_now), isTrue);
      expect(_holdIn(const Duration(minutes: 1)).hasExpired(_now), isFalse);
    });

    test('labels the remaining window in coarse, human units', () {
      expect(_holdIn(const Duration(hours: 23, minutes: 30)).remainingLabel(_now),
          '23 hours');
      expect(_holdIn(const Duration(hours: 1)).remainingLabel(_now), '1 hour');
      expect(_holdIn(const Duration(minutes: 45)).remainingLabel(_now),
          '45 minutes');
      expect(_holdIn(const Duration(minutes: 1)).remainingLabel(_now),
          '1 minute');
      expect(_holdIn(const Duration(seconds: 20)).remainingLabel(_now), isNull);
      expect(_holdIn(const Duration(hours: -1)).remainingLabel(_now), isNull);
    });
  });

  group('ChallengeTerminalReason', () {
    test('parses the premium-lapse cancellation the server can now write', () {
      // Unknown terminal reasons THROW in this parser, so shipping the server
      // value without this case would break the history and result screens for
      // every runner in a challenge cancelled this way.
      expect(
        ChallengeTerminalReason.parse('OWNER_PREMIUM_LAPSED'),
        ChallengeTerminalReason.ownerPremiumLapsed,
      );
      expect(
        ChallengeTerminalReason.ownerPremiumLapsed.wireValue,
        'OWNER_PREMIUM_LAPSED',
      );
    });
  });

  group('ChallengePremiumLapseBanner', () {
    testWidgets('renders nothing when there is no hold', (tester) async {
      await tester.pumpWidget(
        _host(
          const ChallengePremiumLapseBanner(hold: null),
        ),
      );

      expect(find.text(ChallengeCopy.premiumLapseTitle), findsNothing);
      expect(find.text(ChallengeCopy.premiumLapseCta), findsNothing);
    });

    testWidgets('warns with the remaining window and offers the paywall',
        (tester) async {
      await tester.pumpWidget(
        _host(
          ChallengePremiumLapseBanner(
            hold: _holdIn(const Duration(hours: 22)),
            now: _now,
          ),
        ),
      );

      expect(find.text(ChallengeCopy.premiumLapseTitle), findsOneWidget);
      expect(
        find.text(ChallengeCopy.premiumLapseBody('22 hours')),
        findsOneWidget,
      );
      expect(find.text(ChallengeCopy.premiumLapseCta), findsOneWidget);
    });

    testWidgets('falls back to the imminent-removal copy once time runs out',
        (tester) async {
      await tester.pumpWidget(
        _host(
          ChallengePremiumLapseBanner(
            hold: _holdIn(const Duration(seconds: 5)),
            now: _now,
          ),
        ),
      );

      expect(find.text(ChallengeCopy.premiumLapseImminentBody), findsOneWidget);
    });

    testWidgets('invokes the upgrade callback when the CTA is tapped',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          ChallengePremiumLapseBanner(
            hold: _holdIn(const Duration(hours: 5)),
            now: _now,
            onUpgrade: () => taps += 1,
          ),
        ),
      );

      await tester.tap(find.text(ChallengeCopy.premiumLapseCta));
      await tester.pump();

      expect(taps, 1);
    });
  });
}

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );
}
