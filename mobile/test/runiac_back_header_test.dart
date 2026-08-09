import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/core/widgets/runiac_back_header.dart';

void main() {
  testWidgets('summary header keeps a long generated title fully visible', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: RuniacBackHeader(
              title: 'Wednesday Afternoon Run',
              subtitle: '8/7/26 · 9:56 PM',
              trailingWidth: 88,
              trailing: Row(mainAxisSize: MainAxisSize.min),
              scaleTitleToFit: true,
            ),
          ),
        ),
      ),
    );

    final title = tester.widget<Text>(find.text('Wednesday Afternoon Run'));
    expect(title.overflow, isNull);
    expect(
      find.ancestor(
        of: find.text('Wednesday Afternoon Run'),
        matching: find.byType(FittedBox),
      ),
      findsOneWidget,
    );
    expect(
      tester.getRect(find.text('Wednesday Afternoon Run')).right,
      lessThanOrEqualTo(302),
    );
  });
}
