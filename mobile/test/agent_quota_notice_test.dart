import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/formatting/agent_quota_notice.dart';
import 'package:runiac_app/core/widgets/character_guidance_overlay.dart';

void main() {
  group('agentQuotaResetNotice', () {
    test('names the server-supplied reset day', () {
      expect(
        agentQuotaResetNotice(
          retryAfterDate: '2026-08-09',
          subject: 'personalised feedback',
        ),
        'Daily limit reached — personalised feedback unlocks again on '
        '9 August 2026.',
      );
    });

    test('still states that it resets when no date was supplied', () {
      expect(
        agentQuotaResetNotice(
          retryAfterDate: null,
          subject: 'your workout briefing',
        ),
        'Daily limit reached — your workout briefing unlocks again tomorrow.',
      );
    });

    // A malformed value must degrade to the dateless sentence rather than
    // rendering a half-parsed string: the runner is never shown a day the
    // backend did not actually name.
    test('falls back to the dateless notice for a malformed date', () {
      for (final malformed in <String>[
        '',
        '2026-8-9',
        '09-08-2026',
        '2026-08-09T00:00:00Z',
        'tomorrow',
        '2026-13-01',
        '2026-02-30',
      ]) {
        expect(
          agentQuotaResetNotice(retryAfterDate: malformed, subject: 'it'),
          'Daily limit reached — it unlocks again tomorrow.',
          reason: 'malformed input: "$malformed"',
        );
      }
    });

    test('tolerates surrounding whitespace on a valid date', () {
      expect(
        agentQuotaResetNotice(retryAfterDate: ' 2026-01-01 ', subject: 'it'),
        'Daily limit reached — it unlocks again on 1 January 2026.',
      );
    });
  });

  group('guidanceStepsWithLeadingNotice', () {
    const steps = <CharacterGuidanceStep>[
      CharacterGuidanceStep(title: 'Summary', body: 'First body.'),
      CharacterGuidanceStep(title: 'Went well', body: 'Second body.'),
    ];

    test('leads the first page and leaves the page count alone', () {
      final result = guidanceStepsWithLeadingNotice(steps, 'Notice.');

      expect(result, hasLength(2));
      expect(result.first.title, 'Summary');
      expect(result.first.body, 'Notice.\n\nFirst body.');
      expect(result.last.body, 'Second body.');
    });

    test('returns the steps untouched for a null or blank notice', () {
      expect(guidanceStepsWithLeadingNotice(steps, null), same(steps));
      expect(guidanceStepsWithLeadingNotice(steps, '   '), same(steps));
    });

    test('returns an empty step list untouched', () {
      const empty = <CharacterGuidanceStep>[];
      expect(guidanceStepsWithLeadingNotice(empty, 'Notice.'), same(empty));
    });
  });
}
