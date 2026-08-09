import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/services/completed_run_title_formatter.dart';

void main() {
  group('CompletedRunTitleFormatter', () {
    const formatter = CompletedRunTitleFormatter();

    test('formats afternoon completion title from completed timestamp', () {
      final title = formatter.format(
        completedAt: DateTime(2026, 6, 12, 14, 30),
      );

      expect(title, 'Friday Afternoon Run');
    });

    test('formats morning completion title from completed timestamp', () {
      final title = formatter.format(completedAt: DateTime(2026, 6, 13, 8, 10));

      expect(title, 'Saturday Morning Run');
    });

    test('formats evening completion title from completed timestamp', () {
      final title = formatter.format(
        completedAt: DateTime(2026, 6, 14, 18, 45),
      );

      expect(title, 'Sunday Evening Run');
    });

    test('formats late night completion title from completed timestamp', () {
      final title = formatter.format(
        completedAt: DateTime(2026, 6, 15, 23, 20),
      );

      expect(title, 'Monday Night Run');
    });

    test('formats early morning completion as night', () {
      final title = formatter.format(completedAt: DateTime(2026, 6, 16, 3, 30));

      expect(title, 'Tuesday Night Run');
    });

    test(
      'converts a persisted UTC completion into the device local daypart',
      () {
        final completedAt = DateTime.utc(2026, 7, 8, 13);
        final local = completedAt.toLocal();
        final expectedDaypart = switch (local.hour) {
          >= 5 && < 12 => 'Morning',
          >= 12 && < 17 => 'Afternoon',
          >= 17 && < 21 => 'Evening',
          _ => 'Night',
        };

        expect(
          formatter.format(completedAt: completedAt),
          '${_weekday(local.weekday)} $expectedDaypart Run',
        );
      },
    );

    test('formats daypart boundaries from completed timestamp', () {
      expect(
        formatter.format(completedAt: DateTime(2026, 6, 17, 5)),
        'Wednesday Morning Run',
      );
      expect(
        formatter.format(completedAt: DateTime(2026, 6, 17, 12)),
        'Wednesday Afternoon Run',
      );
      expect(
        formatter.format(completedAt: DateTime(2026, 6, 17, 17)),
        'Wednesday Evening Run',
      );
      expect(
        formatter.format(completedAt: DateTime(2026, 6, 17, 21)),
        'Wednesday Night Run',
      );
    });
  });
}

String _weekday(int weekday) => switch (weekday) {
  DateTime.monday => 'Monday',
  DateTime.tuesday => 'Tuesday',
  DateTime.wednesday => 'Wednesday',
  DateTime.thursday => 'Thursday',
  DateTime.friday => 'Friday',
  DateTime.saturday => 'Saturday',
  DateTime.sunday => 'Sunday',
  _ => throw ArgumentError.value(weekday, 'weekday'),
};
