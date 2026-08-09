// Shared Firestore collection-name constants for the newsletter module, so a
// typo in one file cannot silently diverge from another (firestore.rules
// mirrors these names literally — see the deny blocks near the end of that
// file).
export const NEWSLETTER_SUBSCRIBERS_COLLECTION = "newsletterSubscribers";
export const NEWSLETTER_CAMPAIGNS_COLLECTION = "newsletterCampaigns";
export const NEWSLETTER_CAMPAIGN_DELIVERIES_SUBCOLLECTION = "deliveries";
export const NEWSLETTER_RATE_LIMITS_COLLECTION = "newsletterRateLimits";
export const MAIL_COLLECTION = "mail";
