import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/formatting/relative_time.dart';

void main() {
  group('relativeAgoPhrase', () {
    final now = DateTime(2026, 7, 21, 12, 0, 0);

    test('under a minute renders "just now"', () {
      expect(
        relativeAgoPhrase(now.subtract(const Duration(seconds: 30)), now: now),
        'just now',
      );
    });

    test('minutes render singular and plural correctly', () {
      expect(
        relativeAgoPhrase(now.subtract(const Duration(minutes: 1)), now: now),
        '1 minute ago',
      );
      expect(
        relativeAgoPhrase(now.subtract(const Duration(minutes: 45)), now: now),
        '45 minutes ago',
      );
    });

    test('hours render singular and plural correctly', () {
      expect(
        relativeAgoPhrase(now.subtract(const Duration(hours: 1)), now: now),
        '1 hour ago',
      );
      expect(
        relativeAgoPhrase(now.subtract(const Duration(hours: 5)), now: now),
        '5 hours ago',
      );
    });

    test('days render singular and plural correctly', () {
      expect(
        relativeAgoPhrase(now.subtract(const Duration(days: 1)), now: now),
        '1 day ago',
      );
      expect(
        relativeAgoPhrase(now.subtract(const Duration(days: 3)), now: now),
        '3 days ago',
      );
    });

    test('a duration of a month or more renders in months', () {
      expect(
        relativeAgoPhrase(now.subtract(const Duration(days: 60)), now: now),
        '2 months ago',
      );
    });

    test('a duration of a year or more renders in years', () {
      expect(
        relativeAgoPhrase(now.subtract(const Duration(days: 400)), now: now),
        '1 year ago',
      );
    });

    test('a future instant clamps to "just now" instead of a negative duration', () {
      expect(
        relativeAgoPhrase(now.add(const Duration(days: 3)), now: now),
        'just now',
      );
    });

    test('defaults to the real clock when now is omitted', () {
      final justBefore = DateTime.now().subtract(const Duration(seconds: 1));
      expect(relativeAgoPhrase(justBefore), 'just now');
    });
  });
}
