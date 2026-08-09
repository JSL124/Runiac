import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/profile/presentation/app_settings_screen.dart';
import 'package:runiac_app/features/settings/domain/models/app_settings.dart';
import 'package:runiac_app/features/settings/domain/repositories/app_settings_repository.dart';
import 'package:runiac_app/features/settings/domain/repositories/profile_visibility_repository.dart';

class _FakeAppSettingsRepository implements AppSettingsRepository {
  _FakeAppSettingsRepository({AppSettings initial = AppSettings.defaults})
    : _current = initial;

  AppSettings _current;
  AppSettings? lastSaved;

  @override
  Future<AppSettings> loadSettings() async => _current;

  @override
  Future<void> saveSettings(AppSettings settings) async {
    _current = settings;
    lastSaved = settings;
  }
}

class _RecordingProfileVisibilityRepository
    implements ProfileVisibilityRepository {
  _RecordingProfileVisibilityRepository({this.initial = false});

  final bool initial;
  bool? lastSaved;

  @override
  Future<bool> loadStatsHidden() async => initial;

  @override
  Future<void> saveStatsHidden({required bool hidden}) async {
    lastSaved = hidden;
  }
}

class _FailingProfileVisibilityRepository
    implements ProfileVisibilityRepository {
  @override
  Future<bool> loadStatsHidden() async {
    throw const ProfileVisibilityUnavailable();
  }

  @override
  Future<void> saveStatsHidden({required bool hidden}) async {
    throw const ProfileVisibilityUnavailable();
  }
}

void main() {
  testWidgets('tapping Mi selector saves miles as the distance unit', (
    tester,
  ) async {
    final fake = _FakeAppSettingsRepository();

    await tester.pumpWidget(
      MaterialApp(home: AppSettingsScreen(settingsRepository: fake)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-distance-unit-mi')));
    await tester.pumpAndSettle();

    expect(fake.lastSaved, isNotNull);
    expect(fake.lastSaved!.distanceUnit, DistanceUnit.miles);
  });

  testWidgets('toggling haptic switch saves hapticFeedbackEnabled as false', (
    tester,
  ) async {
    final fake = _FakeAppSettingsRepository();

    await tester.pumpWidget(
      MaterialApp(home: AppSettingsScreen(settingsRepository: fake)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings-haptic-switch')));
    await tester.pumpAndSettle();

    expect(fake.lastSaved, isNotNull);
    expect(fake.lastSaved!.hapticFeedbackEnabled, isFalse);
  });

  testWidgets('turning on Private profile stores the hidden preference', (
    tester,
  ) async {
    final visibility = _RecordingProfileVisibilityRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsScreen(
          settingsRepository: _FakeAppSettingsRepository(),
          profileVisibilityRepository: visibility,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('settings-private-profile-switch')),
    );
    await tester.pumpAndSettle();

    expect(visibility.lastSaved, isTrue);
  });

  testWidgets('the switch reflects the stored preference on open', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsScreen(
          settingsRepository: _FakeAppSettingsRepository(),
          profileVisibilityRepository: _RecordingProfileVisibilityRepository(
            initial: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final control = tester.widget<Switch>(
      find.byKey(const ValueKey('settings-private-profile-switch')),
    );
    expect(control.value, isTrue);
  });

  testWidgets('an unreachable preference reads as unavailable, not as off', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsScreen(
          settingsRepository: _FakeAppSettingsRepository(),
          profileVisibilityRepository: _FailingProfileVisibilityRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings-private-profile-unavailable')),
      findsOneWidget,
    );
    final control = tester.widget<Switch>(
      find.byKey(const ValueKey('settings-private-profile-switch')),
    );
    // Read-only rather than showing a value nobody confirmed.
    expect(control.onChanged, isNull);
  });

  testWidgets('a rejected save reverts the switch', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AppSettingsScreen(
          settingsRepository: _FakeAppSettingsRepository(),
          profileVisibilityRepository: _RejectingSaveVisibilityRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('settings-private-profile-switch')),
    );
    await tester.pumpAndSettle();

    final control = tester.widget<Switch>(
      find.byKey(const ValueKey('settings-private-profile-switch')),
    );
    expect(control.value, isFalse);
    expect(find.byType(SnackBar), findsOneWidget);
  });
}

class _RejectingSaveVisibilityRepository
    implements ProfileVisibilityRepository {
  @override
  Future<bool> loadStatsHidden() async => false;

  @override
  Future<void> saveStatsHidden({required bool hidden}) async {
    throw const ProfileVisibilityUnavailable();
  }
}
