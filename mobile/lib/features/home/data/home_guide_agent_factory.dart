import '../../run/data/run_repository_factory.dart'
    show RuniacFirebaseRuntimeConfig;
import '../domain/guide/home_guide_agent.dart';
import '../domain/guide/rule_based_home_guide_agent.dart';
import 'cloud_function_home_guide_agent.dart';

/// Selects the [HomeGuideAgent] implementation for the current runtime,
/// mirroring [RuniacFirebaseRuntimeConfig]-gated selection used by
/// `RunRepositoryFactory`.
///
/// A Cloud Function-backed agent is used only when Firebase (emulator or
/// production) is active; otherwise the offline rule-based agent is used
/// directly, so the guide seam never depends on Firebase being configured.
class HomeGuideAgentFactory {
  const HomeGuideAgentFactory._();

  static HomeGuideAgent create({RuniacFirebaseRuntimeConfig? config}) {
    final runtimeConfig =
        config ?? RuniacFirebaseRuntimeConfig.fromEnvironment();
    if (runtimeConfig.useFirebaseEmulator ||
        runtimeConfig.useProductionFirebase) {
      return CloudFunctionHomeGuideAgent();
    }
    return const RuleBasedHomeGuideAgent();
  }
}
