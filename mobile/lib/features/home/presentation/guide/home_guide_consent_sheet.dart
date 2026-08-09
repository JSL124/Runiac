import 'package:flutter/material.dart';

import 'home_guide_consent_disclosure.dart';

/// Shows the one-time Home guide data-use consent bottom sheet.
///
/// Returns `true` when the user agrees, `false` when they disagree. The sheet
/// requires an explicit decision (it cannot be dismissed by tapping outside,
/// dragging, or the system back gesture); `null` is only returned in the
/// defensive case of a programmatic pop. The caller performs the consent write.
Future<bool?> showHomeGuideConsentSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => const _HomeGuideConsentSheet(),
  );
}

class _HomeGuideConsentSheet extends StatelessWidget {
  const _HomeGuideConsentSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: SafeArea(
        child: Padding(
          key: const ValueKey<String>('homeGuideConsentSheet'),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(homeGuideConsentTitle, style: theme.textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(
                homeGuideConsentDisclosure,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const ValueKey<String>('homeGuideConsentAgree'),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(homeGuideConsentAgreeLabel),
                ),
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  key: const ValueKey<String>('homeGuideConsentDisagree'),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(homeGuideConsentDisagreeLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
