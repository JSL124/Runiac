import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/runiac_theme.dart';
import '../../data/firebase_account_deletion_repository.dart';
import '../../../auth/domain/runiac_auth_service.dart';
import '../delete_account_screen.dart';

/// QA surface for the delete-account flow:
///
///   flutter run --dart-define=RUNIAC_QA_SURFACE=delete_account
///
/// Exists because the real entry point sits behind a signed-in Account screen,
/// and the only way to exercise it end to end for real is to actually delete a
/// real account — which is not a thing anyone can do twice. This host renders
/// the real `DeleteAccountScreen` with a stub repository, so the copy, the
/// typed-DELETE gate, the confirmation dialog, and both outcome paths can be
/// checked on a device without a Firebase account and without erasing
/// anything.
///
/// Debug-only, like every other QA launcher: `kReleaseMode` short-circuits it
/// before the surface name is even compared.
const deleteAccountQaSurfaceName = 'delete_account';

const _qaSurface = String.fromEnvironment('RUNIAC_QA_SURFACE');

Widget? buildDeleteAccountQaAppFromEnvironment() {
  return buildDeleteAccountQaApp(releaseMode: kReleaseMode, surface: _qaSurface);
}

@visibleForTesting
Widget? buildDeleteAccountQaApp({
  required bool releaseMode,
  required String surface,
}) {
  if (releaseMode || surface != deleteAccountQaSurfaceName) {
    return null;
  }

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Runiac Delete Account QA',
    theme: buildRuniacTheme(),
    home: const _DeleteAccountQaHost(),
  );
}

class _DeleteAccountQaHost extends StatefulWidget {
  const _DeleteAccountQaHost();

  @override
  State<_DeleteAccountQaHost> createState() => _DeleteAccountQaHostState();
}

class _DeleteAccountQaHostState extends State<_DeleteAccountQaHost> {
  bool _shouldFail = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Delete account QA',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Nothing is deleted. The repository below is a stub.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  value: _shouldFail,
                  onChanged: (value) => setState(() => _shouldFail = value),
                  title: const Text('Make the request fail'),
                  subtitle: const Text(
                    'Checks that a failure keeps you on the screen',
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DeleteAccountScreen(
                        authRepository: const _QaAuthRepository(),
                        deletionRepository: _QaDeletionRepository(
                          shouldFail: _shouldFail,
                        ),
                      ),
                    ),
                  ),
                  child: const Text('Open Delete account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QaDeletionRepository implements AccountDeletionRepository {
  const _QaDeletionRepository({required this.shouldFail});

  final bool shouldFail;

  @override
  Future<bool> requestAccountDeletion() async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (shouldFail) {
      throw const AccountDeletionException(
        code: 'permission-denied',
        userMessage: 'This account cannot be deleted right now. Please contact support.',
      );
    }
    return true;
  }
}

/// Sign-out is a no-op here; the screen pops back to this host either way.
class _QaAuthRepository implements RuniacAuthRepository {
  const _QaAuthRepository();

  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
