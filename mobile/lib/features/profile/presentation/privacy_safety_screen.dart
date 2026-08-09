import 'package:flutter/material.dart';

import '../../../core/legal/runiac_legal_link_launcher.dart';
import '../../../core/legal/runiac_legal_urls.dart';
import '../../../core/legal/runiac_url_opener.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_back_header.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../../home/domain/guide/home_guide_consent.dart';
import '../../home/presentation/guide/home_guide_consent_disclosure.dart';

/// Account → Privacy & Safety. Hosts the personalized-guide data-use consent,
/// letting the user allow it or stop it (disagree) at any time, and links out
/// to the hosted Privacy Policy.
///
/// The authoritative consent value is owned server-side; this screen only reads
/// it back and forwards the user's choice to [HomeGuideConsentRepository]. It
/// never computes or stores any backend-owned value.
class PrivacySafetyScreen extends StatefulWidget {
  const PrivacySafetyScreen({
    required this.consentRepository,
    this.legalUrlOpener = const UrlLauncherOpener(),
    super.key,
  });

  final HomeGuideConsentRepository consentRepository;

  /// Seam so tests can observe the policy link without launching a browser.
  final RuniacUrlOpener legalUrlOpener;

  @override
  State<PrivacySafetyScreen> createState() => _PrivacySafetyScreenState();
}

class _PrivacySafetyScreenState extends State<PrivacySafetyScreen> {
  HomeGuideConsentStatus _status = HomeGuideConsentStatus.unknown;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await widget.consentRepository.read();
    if (!mounted) {
      return;
    }
    setState(() => _status = status);
  }

  Future<void> _setGranted(bool granted) async {
    if (_updating) {
      return;
    }
    setState(() => _updating = true);
    try {
      final status = await widget.consentRepository.update(granted: granted);
      if (!mounted) {
        return;
      }
      setState(() => _status = status);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update guide data use. Please try again.'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLoading = _status == HomeGuideConsentStatus.unknown;
    final granted = _status == HomeGuideConsentStatus.granted;
    return Scaffold(
      backgroundColor: RuniacColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            RuniacBackHeader(
              title: 'Privacy & Safety',
              tooltip: 'Back to Account',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      key: const ValueKey<String>(
                        'privacySafetyGuideConsentCard',
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: RuniacColors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: RuniacColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            homeGuideConsentTitle,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            homeGuideConsentDisclosure,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 8),
                          if (isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: LinearProgressIndicator(),
                            )
                          else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Personalized guide',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        granted
                                            ? 'On — your recent run totals personalize the guide.'
                                            : 'Off — the guide shows your plan without personalizing it.',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 6),
                                      // The consent covers the Premium AI
                                      // coach only. Basic accounts read
                                      // today's plan on-device, so nothing
                                      // they see depends on this switch.
                                      Text(
                                        'This applies to the Premium AI coach only. On Basic, '
                                        "today's plan is read out on your device and no run "
                                        'data is sent.',
                                        key: const ValueKey<String>(
                                          'privacySafetyGuideConsentTierNote',
                                        ),
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  RuniacColors.textSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Switch(
                                  key: const ValueKey<String>(
                                    'privacySafetyGuideConsentSwitch',
                                  ),
                                  value: granted,
                                  onChanged: _updating
                                      ? null
                                      : (value) => _setGranted(value),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    RuniacTappableSurface(
                      key: const ValueKey<String>('privacySafetyPolicyRow'),
                      semanticLabel: 'Read our full Privacy Policy',
                      borderRadius: BorderRadius.circular(18),
                      decoration: BoxDecoration(
                        color: RuniacColors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: RuniacColors.border),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 16,
                      ),
                      onTap: () => openRuniacLegalUrl(
                        context,
                        opener: widget.legalUrlOpener,
                        url: RuniacLegalUrls.privacy,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Read our full Privacy Policy',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.open_in_new_rounded,
                            color: RuniacColors.textSecondary,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
