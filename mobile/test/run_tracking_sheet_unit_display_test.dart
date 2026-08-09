import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/run/domain/models/run_tracking_state.dart';
import 'package:runiac_app/features/run/presentation/widgets/run_tracking_sheet_content.dart';
import 'package:runiac_app/features/settings/domain/models/app_settings.dart';

RunTrackingState _stateWith({
  required int distanceMeters,
  required int currentPaceSecondsPerKm,
}) {
  return const RunTrackingState.idle().copyWith(
    phase: RunTrackingPhase.active,
    elapsedSeconds: 600,
    distanceMeters: distanceMeters,
    averagePaceSecondsPerKm: currentPaceSecondsPerKm,
    currentPaceSecondsPerKm: currentPaceSecondsPerKm,
  );
}

Widget _harness(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets(
    'renders converted distance and pace in miles when distanceUnit is miles',
    (tester) async {
      final state = _stateWith(distanceMeters: 2000, currentPaceSecondsPerKm: 300);

      await tester.pumpWidget(
        _harness(
          RunTrackingSheetContent(
            state: state,
            onPause: () {},
            onResume: () {},
            onEnd: () {},
            distanceUnit: DistanceUnit.miles,
          ),
        ),
      );
      await tester.pump();

      // 2.00 km * 0.621371 = 1.242742 -> "1.24" mi.
      expect(find.text('1.24'), findsOneWidget);
      expect(find.text('mi'), findsOneWidget);
      expect(find.text('km'), findsNothing);

      // 300 s/km -> 300 / 0.621371 = 482.80... -> rounds to 483 s/mi = 08:03/mi.
      expect(find.text('08:03/mi'), findsOneWidget);
      expect(find.textContaining('/km'), findsNothing);
    },
  );

  testWidgets(
    'kilometers path renders exactly as before (default distanceUnit)',
    (tester) async {
      final state = _stateWith(distanceMeters: 2000, currentPaceSecondsPerKm: 300);

      await tester.pumpWidget(
        _harness(
          RunTrackingSheetContent(
            state: state,
            onPause: () {},
            onResume: () {},
            onEnd: () {},
          ),
        ),
      );
      await tester.pump();

      expect(find.text('2.00'), findsOneWidget);
      expect(find.text('km'), findsOneWidget);
      expect(find.text('05:00/km'), findsOneWidget);
      expect(find.textContaining('/mi'), findsNothing);
    },
  );
}
