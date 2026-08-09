import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiac_app/features/auth/domain/runiac_auth_service.dart';
import 'package:runiac_app/features/profile/data/firebase_account_deletion_repository.dart';
import 'package:runiac_app/features/profile/presentation/delete_account_screen.dart';
import 'package:runiac_app/features/profile/presentation/widgets/account_delete_row.dart';

// The client half of account deletion. Everything that actually erases data is
// server-owned, so what is worth pinning here is the consent gate and the
// failure behaviour:
//
//   - the request cannot be sent until DELETE is typed AND the dialog confirmed
//   - a failed request keeps the runner signed in and on the screen, because a
//     runner who is signed out after a failure cannot tell whether their
//     account is gone, and cannot retry
//   - a successful request signs out and leaves the screen

void main() {
  testWidgets('the row opens the delete screen', (tester) async {
    final auth = _FakeAuthRepository();
    final deletion = _FakeDeletionRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AccountDeleteRow(
            authRepository: auth,
            deletionRepository: deletion,
          ),
        ),
      ),
    );

    expect(find.text('Delete account'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('account_delete_row')));
    await tester.pumpAndSettle();

    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.text('This cannot be undone'), findsOneWidget);
  });

  testWidgets('states what is deleted and what is kept', (tester) async {
    await _pumpScreen(tester, _FakeAuthRepository(), _FakeDeletionRepository());

    expect(find.text('What is deleted'), findsOneWidget);
    expect(find.text('What is kept, without your name on it'), findsOneWidget);
    // The retention decision is the one thing a runner could reasonably be
    // surprised by later, so it must be on the screen, not only in the policy.
    expect(
      find.text('Reports you filed or that were filed about you'),
      findsOneWidget,
    );
  });

  testWidgets('the submit button is inert until DELETE is typed', (tester) async {
    final deletion = _FakeDeletionRepository();
    await _pumpScreen(tester, _FakeAuthRepository(), deletion);

    final button = find.byKey(const ValueKey('delete_account_submit'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.enterText(
      find.byKey(const ValueKey('delete_account_confirmation_field')),
      'delete',
    );
    await tester.pump();
    expect(
      tester.widget<FilledButton>(button).onPressed,
      isNull,
      reason: 'the confirmation is case-sensitive',
    );

    await tester.enterText(
      find.byKey(const ValueKey('delete_account_confirmation_field')),
      'DELETE',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    expect(deletion.callCount, 0);
  });

  testWidgets('dismissing the dialog sends nothing', (tester) async {
    final auth = _FakeAuthRepository();
    final deletion = _FakeDeletionRepository();
    await _pumpScreen(tester, auth, deletion);

    await _typeConfirmation(tester);
    await _tapSubmit(tester);

    expect(find.text('Delete your account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(deletion.callCount, 0);
    expect(auth.signOutCount, 0);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
  });

  testWidgets('confirming requests the deletion and signs out', (tester) async {
    final auth = _FakeAuthRepository();
    final deletion = _FakeDeletionRepository();
    await _pumpScreen(tester, auth, deletion);

    await _typeConfirmation(tester);
    await _tapSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('delete_account_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(deletion.callCount, 1);
    expect(auth.signOutCount, 1);
    expect(find.byType(DeleteAccountScreen), findsNothing);
  });

  testWidgets('a failure keeps the runner signed in and on the screen', (tester) async {
    final auth = _FakeAuthRepository();
    final deletion = _FakeDeletionRepository(
      error: const AccountDeletionException(
        code: 'permission-denied',
        userMessage: 'This account cannot be deleted right now.',
      ),
    );
    await _pumpScreen(tester, auth, deletion);

    await _typeConfirmation(tester);
    await _tapSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('delete_account_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(auth.signOutCount, 0);
    expect(find.byType(DeleteAccountScreen), findsOneWidget);
    expect(find.text('This account cannot be deleted right now.'), findsOneWidget);
    // Still retryable.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('delete_account_submit')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('a sign-out failure still leaves the screen', (tester) async {
    // The server already revoked this session, so the local sign-out failing
    // must not look like a failed deletion.
    final auth = _FakeAuthRepository(failSignOut: true);
    final deletion = _FakeDeletionRepository();
    await _pumpScreen(tester, auth, deletion);

    await _typeConfirmation(tester);
    await _tapSubmit(tester);
    await tester.tap(find.byKey(const ValueKey('delete_account_dialog_confirm')));
    await tester.pumpAndSettle();

    expect(deletion.callCount, 1);
    expect(find.byType(DeleteAccountScreen), findsNothing);
  });

  testWidgets('renders without overflow at 360px and textScale 1.3', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          home: DeleteAccountScreen(
            authRepository: _FakeAuthRepository(),
            deletionRepository: _FakeDeletionRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpScreen(
  WidgetTester tester,
  RuniacAuthRepository auth,
  AccountDeletionRepository deletion,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DeleteAccountScreen(
                  authRepository: auth,
                  deletionRepository: deletion,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

// The screen is taller than the default 800x600 test viewport, so the submit
// button has to be scrolled into view before it can be tapped.
Future<void> _tapSubmit(WidgetTester tester) async {
  final submit = find.byKey(const ValueKey('delete_account_submit'));
  await tester.ensureVisible(submit);
  await tester.pumpAndSettle();
  await tester.tap(submit);
  await tester.pumpAndSettle();
}

Future<void> _typeConfirmation(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey('delete_account_confirmation_field')),
    'DELETE',
  );
  await tester.pump();
}

class _FakeAuthRepository implements RuniacAuthRepository {
  _FakeAuthRepository({this.failSignOut = false});

  final bool failSignOut;
  int signOutCount = 0;

  @override
  Future<void> signOut() async {
    if (failSignOut) {
      throw Exception('offline');
    }
    signOutCount += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDeletionRepository implements AccountDeletionRepository {
  _FakeDeletionRepository({this.error});

  final Object? error;
  int callCount = 0;

  @override
  Future<bool> requestAccountDeletion() async {
    callCount += 1;
    final error = this.error;
    if (error != null) {
      throw error;
    }
    return true;
  }
}
