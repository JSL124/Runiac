import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/home/presentation/stage_map/home_stage_map.dart';
import 'package:runiac_app/features/profile/presentation/app_settings_screen.dart';
import 'package:runiac_app/features/settings/domain/models/app_settings.dart';
import 'package:runiac_app/features/settings/domain/repositories/app_settings_repository.dart';

class _FakeAppSettingsRepository implements AppSettingsRepository {
  AppSettings _settings = AppSettings.defaults;

  @override
  Future<AppSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _settings = settings;
  }
}

/// The stage map alone, with only the Menu wiring this test cares about. It
/// keeps the assertion on the Menu itself rather than on the whole Home tree.
Widget _stageMap({required VoidCallback onOpenSettings}) {
  return MaterialApp(
    home: Scaffold(
      body: HomeStageMap(
        onNotifications: () {},
        onProfile: () {},
        onTapTodayStage: () {},
        onOpenSettings: onOpenSettings,
      ),
    ),
  );
}

void main() {
  testWidgets('the Home Menu carries a Settings item that fires its callback', (
    tester,
  ) async {
    var opened = 0;

    await tester.pumpWidget(_stageMap(onOpenSettings: () => opened += 1));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_menu_settings')), findsNothing);

    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_menu_settings')), findsOneWidget);

    await tester.tap(find.byKey(const Key('home_menu_settings')));
    await tester.pumpAndSettle();

    expect(opened, 1);
    // Selecting a row closes the panel, the same as every other Menu item.
    expect(find.byKey(const Key('home_menu_settings')), findsNothing);
  });

  testWidgets('a Settings tap with no handler wired just closes the Menu', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeStageMap(
            onNotifications: () {},
            onProfile: () {},
            onTapTodayStage: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_menu_settings')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('home_menu_settings')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Settings screen opens with the visibility section', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsScreen(
          settingsRepository: _FakeAppSettingsRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PROFILE VISIBILITY'), findsOneWidget);
    expect(find.text('Private profile'), findsOneWidget);
  });
}
