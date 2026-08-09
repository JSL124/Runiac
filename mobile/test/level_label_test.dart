import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/formatting/level_label.dart';

void main() {
  group('compactLevelLabel', () {
    test('an empty or blank label compacts to empty', () {
      expect(compactLevelLabel(''), '');
      expect(compactLevelLabel('   '), '');
    });

    test('a "Level N" label compacts to "Lv.N"', () {
      expect(compactLevelLabel('Level 12'), 'Lv.12');
      expect(compactLevelLabel('level 7'), 'Lv.7');
      expect(compactLevelLabel('LEVEL 3'), 'Lv.3');
    });

    test('extra whitespace around the label and number is trimmed', () {
      expect(compactLevelLabel('  Level   9  '), 'Lv.9');
    });

    test('a label already in compact form passes through unchanged', () {
      expect(compactLevelLabel('Lv.12'), 'Lv.12');
    });

    test('an unrecognized label shape passes through unchanged', () {
      expect(compactLevelLabel('Tier 4'), 'Tier 4');
    });
  });
}
