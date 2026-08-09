/// Shared, user-facing copy for the Home guide personalized-data-use consent.
///
/// Presented identically in the onboarding bottom sheet (first Home entry) and
/// the Account → Privacy & Safety screen so the disclosure stays consistent.
/// Consent is enforced server-side before any run totals are used; this copy is
/// the disclosure shown before the user decides.
const String homeGuideConsentTitle = 'Personalized guide data use';

const String homeGuideConsentDisclosure =
    'Runiac uses totals from your recent validated runs — frequency, '
    'distance, active time, and eligible pace — to personalize today’s three '
    'guide messages. Raw GPS routes, activity IDs, exact timestamps, profile '
    'data, and health data are not sent to the AI provider. You can change '
    'this anytime from Account → Privacy & Safety.';

/// Primary/secondary button labels, phrased for a first-time decision.
const String homeGuideConsentAgreeLabel = 'Allow personalized guide';
const String homeGuideConsentDisagreeLabel = 'Not now';
