import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/characters/runner_character.dart';
import '../../../../core/theme/runiac_colors.dart';
import '../../../../core/theme/runiac_theme.dart';
import '../../../../core/widgets/runiac_buttons.dart';
import '../../../profile/presentation/current_session_user_account.dart';
import '../../../you/presentation/widgets/premium_upsell_section.dart';
import '../../domain/models/feature_access_read_model.dart';
import '../../domain/repositories/feature_access_repository.dart';
import '../current_session_feature_access.dart';
import '../current_session_paywall_config.dart';
import '../premium_paywall_sheet.dart';

/// Debug-only QA surface that boots straight into the premium paywall sheet
/// with the built-in default copy, skipping auth/onboarding entirely. The
/// host screen behind the sheet also previews the You > Plans premium upsell
/// section (the static account scope resolves to Basic, so it renders).
///
/// Launch (from mobile/):
///   flutter run --dart-define=RUNIAC_QA_SURFACE=premium_paywall
/// Optional character override (blue | cap | pink | purple):
///   --dart-define=RUNIAC_QA_PAYWALL_CHARACTER=pink
const premiumPaywallQaSurfaceName = 'premium_paywall';

const _qaSurface = String.fromEnvironment('RUNIAC_QA_SURFACE');
const _qaCharacter = String.fromEnvironment(
  'RUNIAC_QA_PAYWALL_CHARACTER',
  defaultValue: 'blue',
);

Widget? buildPremiumPaywallQaAppFromEnvironment() {
  return buildPremiumPaywallQaApp(
    releaseMode: kReleaseMode,
    surface: _qaSurface,
    characterId: _qaCharacter,
  );
}

@visibleForTesting
Widget? buildPremiumPaywallQaApp({
  required bool releaseMode,
  required String surface,
  required String characterId,
}) {
  if (releaseMode || surface != premiumPaywallQaSurfaceName) {
    return null;
  }
  return _PremiumPaywallQaApp(
    character: runnerCharacterFromId(characterId) ?? RunnerCharacter.blue,
  );
}

class _PremiumPaywallQaApp extends StatefulWidget {
  const _PremiumPaywallQaApp({required this.character});

  final RunnerCharacter character;

  @override
  State<_PremiumPaywallQaApp> createState() => _PremiumPaywallQaAppState();
}

class _PremiumPaywallQaAppState extends State<_PremiumPaywallQaApp> {
  final SelectedRunnerCharacterStore _characterStore =
      SelectedRunnerCharacterStore();
  final CurrentSessionPaywallConfig _paywallConfigStore =
      CurrentSessionPaywallConfig();
  // Static repository resolves to the Basic tier, which is exactly what the
  // upsell-section preview needs.
  final CurrentSessionUserAccount _userAccountStore =
      CurrentSessionUserAccount();
  // Several premium-checked features so QA sees the staggered list entrance.
  final CurrentSessionFeatureAccess _featureAccessStore =
      CurrentSessionFeatureAccess(
        repository: const _QaFeatureAccessRepository(),
      );

  @override
  void initState() {
    super.initState();
    _characterStore.select(widget.character);
  }

  @override
  void dispose() {
    _characterStore.dispose();
    _paywallConfigStore.dispose();
    _userAccountStore.dispose();
    _featureAccessStore.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SelectedRunnerCharacterScope(
      store: _characterStore,
      child: CurrentSessionUserAccountScope(
        store: _userAccountStore,
        child: PaywallConfigScope(
          store: _paywallConfigStore,
          child: FeatureAccessScope(
            store: _featureAccessStore,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Runiac Paywall QA',
              theme: buildRuniacTheme(),
              home: const _PremiumPaywallQaHost(),
            ),
          ),
        ),
      ),
    );
  }
}

/// QA-only checklist with several premium-checked features so the upsell
/// list's staggered entrance is visible without seeding an emulator doc.
class _QaFeatureAccessRepository implements FeatureAccessRepository {
  const _QaFeatureAccessRepository();

  @override
  Future<FeatureAccessReadModel> loadFeatureAccess() async {
    return const FeatureAccessReadModel(
      premiumFeatureKeys: [
        'advancedAnalysis',
        'activityFeedback',
        'workoutBriefing',
        'shareCards',
        'shareRouteToFeed',
      ],
    );
  }
}

class _PremiumPaywallQaHost extends StatefulWidget {
  const _PremiumPaywallQaHost();

  @override
  State<_PremiumPaywallQaHost> createState() => _PremiumPaywallQaHostState();
}

class _PremiumPaywallQaHostState extends State<_PremiumPaywallQaHost> {
  @override
  void initState() {
    super.initState();
    // Present the sheet as soon as the first frame is up so QA lands
    // directly on it; the button below reopens it after a dismiss.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        PremiumPaywallSheet.show(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final character =
        SelectedRunnerCharacterScope.maybeOf(context)?.selectedOrDefault ??
        RunnerCharacter.blue;
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 24),
                Text(
                  'Paywall QA · ${character.displayName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: RuniacColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: () => PremiumPaywallSheet.show(context),
                  style: RuniacButtonStyles.primary(
                    minimumSize: const Size(220, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text('Open paywall'),
                ),
                const SizedBox(height: 28),
                // You > Plans upsell-section preview (renders because the QA
                // account scope resolves to Basic).
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: const PremiumUpsellSection(),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
