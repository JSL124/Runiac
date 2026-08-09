import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/characters/runner_character.dart';
import '../../../core/legal/runiac_legal_link_launcher.dart';
import '../../../core/legal/runiac_legal_urls.dart';
import '../../../core/legal/runiac_url_opener.dart';
import '../../../core/theme/runiac_colors.dart';
import '../../../core/widgets/runiac_bottom_sheet_handle.dart';
import '../../../core/widgets/runiac_buttons.dart';
import '../domain/models/paywall_config_read_model.dart';
import 'current_session_paywall_config.dart';
import 'widgets/paywall_character_idle.dart';
import 'widgets/paywall_feature_list.dart';

enum _PaywallPlanSelection { monthly, yearly }

/// Premium upsell sheet shown when a Basic runner taps a premium feature.
///
/// Everything on the sheet (title, badge, feature rows, prices, CTA, footer)
/// is display copy published by the admin console to `config/paywall`. The
/// sheet never writes any state: premium is admin-granted today, so the CTA
/// plays a friendly in-place "coming soon" note instead of starting a
/// purchase. Real feature enforcement stays server-side.
class PremiumPaywallSheet extends StatefulWidget {
  const PremiumPaywallSheet({
    this.legalUrlOpener = const UrlLauncherOpener(),
    super.key,
  });

  /// Seam so tests can observe the footer links without launching a browser.
  final RuniacUrlOpener legalUrlOpener;

  /// Presents the paywall with the app's canonical modal-sheet chrome.
  ///
  /// Kicks off the one-shot `config/paywall` load first; the sheet renders
  /// the built-in defaults instantly and rebuilds if the doc arrives.
  static Future<void> show(BuildContext context) {
    unawaited(PaywallConfigScope.maybeRead(context)?.ensureLoaded());
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      builder: (context) => const FractionallySizedBox(
        heightFactor: 0.93,
        child: PremiumPaywallSheet(),
      ),
    );
  }

  @override
  State<PremiumPaywallSheet> createState() => _PremiumPaywallSheetState();
}

class _PremiumPaywallSheetState extends State<PremiumPaywallSheet> {
  var _selection = _PaywallPlanSelection.yearly;
  var _showComingSoonNote = false;
  var _celebrateTick = 0;
  Timer? _comingSoonRevertTimer;

  @override
  void dispose() {
    _comingSoonRevertTimer?.cancel();
    super.dispose();
  }

  void _onSubscribePressed() {
    _comingSoonRevertTimer?.cancel();
    setState(() {
      _showComingSoonNote = true;
      _celebrateTick += 1;
    });
    _comingSoonRevertTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() {
          _showComingSoonNote = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final config =
        PaywallConfigScope.maybeOf(context)?.config ??
        PaywallConfigReadModel.defaults;
    final character =
        SelectedRunnerCharacterScope.maybeOf(context)?.selectedOrDefault ??
        RunnerCharacter.blue;
    final selectedOption = _selection == _PaywallPlanSelection.yearly
        ? config.yearly
        : config.monthly;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: RuniacColors.sectionSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x292F51C8),
            blurRadius: 40,
            offset: Offset(0, -14),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: RuniacBottomSheetHandle(
                  width: 40,
                  height: 5,
                  color: RuniacColors.primaryBlue.withValues(alpha: 0.18),
                  borderRadius: 99,
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  key: const Key('paywall-close-button'),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    foregroundColor: RuniacColors.textSecondary,
                    minimumSize: const Size(40, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.close_rounded, size: 24),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        config.title,
                        key: const Key('paywall-title'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                          color: RuniacColors.textPrimary,
                        ),
                      ),
                      if (config.badge.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            key: const Key('paywall-badge'),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: RuniacColors.accentOrange.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              config.badge,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: RuniacColors.accentOrange,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 18),
                      _FeatureCardWithCharacter(
                        config: config,
                        character: character,
                        celebrateTick: _celebrateTick,
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: _PlanPriceCard(
                              key: const Key('paywall-plan-yearly'),
                              option: config.yearly,
                              selected:
                                  _selection == _PaywallPlanSelection.yearly,
                              onTap: () => setState(() {
                                _selection = _PaywallPlanSelection.yearly;
                              }),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PlanPriceCard(
                              key: const Key('paywall-plan-monthly'),
                              option: config.monthly,
                              selected:
                                  _selection == _PaywallPlanSelection.monthly,
                              onTap: () => setState(() {
                                _selection = _PaywallPlanSelection.monthly;
                              }),
                            ),
                          ),
                        ],
                      ),
                      if (selectedOption.note.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          selectedOption.note,
                          key: const Key('paywall-plan-note'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: RuniacColors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('paywall-subscribe-button'),
                onPressed: _onSubscribePressed,
                style: RuniacButtonStyles.primary(
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                  elevation: 0,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    _showComingSoonNote
                        ? 'Coming soon'
                        : '${config.ctaLabel} · ${selectedOption.price} '
                              '${selectedOption.period}',
                    key: ValueKey(_showComingSoonNote),
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: _showComingSoonNote
                    ? const Padding(
                        padding: EdgeInsets.only(top: 10),
                        child: Text(
                          'Premium is invite-only for now — the Runiac team '
                          'grants it to early runners.',
                          key: Key('paywall-coming-soon-note'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            color: RuniacColors.textSecondary,
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              _PaywallFooterLinks(
                footer: config.footer,
                opener: widget.legalUrlOpener,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The white feature card with the selected character peeking over its
/// top-right corner (the Notion-cat spot), plus a couple of sparkle accents.
class _FeatureCardWithCharacter extends StatelessWidget {
  const _FeatureCardWithCharacter({
    required this.config,
    required this.character,
    required this.celebrateTick,
  });

  final PaywallConfigReadModel config;
  final RunnerCharacter character;
  final int celebrateTick;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Padding(
          // Headroom so the overlapping character never clips at the top.
          padding: const EdgeInsets.only(top: 34),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 16, 10, 12),
            decoration: BoxDecoration(
              color: RuniacColors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: RuniacColors.cardBorder),
              boxShadow: const [
                BoxShadow(
                  color: RuniacColors.softCardShadow,
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: PaywallFeatureList(
              features: config.features,
              highlightIntervalMs: config.highlightIntervalMs,
            ),
          ),
        ),
        // Feet land ~30px below the card's top edge (card starts at 34 in
        // this stack): footprint height for width 84 is ~126, so -62 puts
        // the character peeking over the corner without covering row text.
        Positioned(
          top: -62,
          right: 8,
          child: PaywallCharacterIdle(
            character: character,
            width: 84,
            celebrateTick: celebrateTick,
          ),
        ),
        const Positioned(
          top: 6,
          left: 6,
          child: Icon(
            Icons.auto_awesome_rounded,
            size: 20,
            color: RuniacColors.accentOrange,
          ),
        ),
      ],
    );
  }
}

class _PlanPriceCard extends StatelessWidget {
  const _PlanPriceCard({
    required this.option,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final PaywallPriceOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${option.price} ${option.period}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? RuniacColors.sectionSurfaceStrong
                : RuniacColors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? RuniacColors.primaryBlue
                  : RuniacColors.cardBorder,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                option.price,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  height: 1.1,
                  color: selected
                      ? RuniacColors.primaryBlue
                      : RuniacColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                option.period,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: RuniacColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaywallFooterLinks extends StatelessWidget {
  const _PaywallFooterLinks({required this.footer, required this.opener});

  final PaywallFooterConfig footer;
  final RuniacUrlOpener opener;

  @override
  Widget build(BuildContext context) {
    // App Store Guideline 3.1.2 requires functional Terms/EULA and privacy
    // links on a subscription surface, so these open the hosted documents.
    // The labels and visibility stay admin-published; the destinations do not.
    final links = <({String label, String url})>[
      if (footer.showTerms)
        (label: footer.termsLabel, url: RuniacLegalUrls.terms),
      if (footer.showPrivacy)
        (label: footer.privacyLabel, url: RuniacLegalUrls.privacy),
    ];
    if (links.isEmpty) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 2),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        children: [
          for (final link in links)
            RuniacTappableSurface(
              semanticLabel: link.label,
              borderRadius: BorderRadius.circular(6),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              onTap: () =>
                  openRuniacLegalUrl(context, opener: opener, url: link.url),
              child: Text(
                link.label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: RuniacColors.textSecondary,
                  decoration: TextDecoration.underline,
                  decorationColor: RuniacColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
