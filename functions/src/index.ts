// Every Cloud Function Runiac deploys, in one place.
//
// Firebase only deploys what this file exports, so adding a function elsewhere
// has no effect until it is re-exported here — and removing a line here
// *deletes* the deployed function on the next `firebase deploy`.
//
// The grouping below is by feature, and it is worth reading as a map of what
// the backend owns: run completion and progression, the LLM coaching agents,
// feed and social, leaderboard aggregation, notifications, moderation,
// newsletter, and account deletion.

export { completeRun } from "./run/completeRun.js";
export { completeCoolDown } from "./run/completeCoolDown.js";
export { homeGuideAgent } from "./agent/homeGuideAgent.js";
export { homeGuideConsent } from "./agent/homeGuideConsent.js";
export { submitFeedback } from "./feedback/submitFeedback.js";
export { subscribeNewsletter } from "./newsletter/subscribeNewsletter.js";
export { confirmNewsletterSubscription } from "./newsletter/confirmNewsletterSubscription.js";
export { unsubscribeNewsletter } from "./newsletter/unsubscribeNewsletter.js";
export { newsletterCampaignQueued } from "./newsletter/newsletterCampaignQueued.js";
export { sweepUnconfirmedSubscribers } from "./newsletter/sweepUnconfirmedSubscribers.js";
export { reportAppError } from "./errors/reportAppError.js";
export { activityFeedbackAgent } from "./agent/activityFeedbackAgent.js";
export { workoutBriefingAgent } from "./agent/workoutBriefingAgent.js";
export { registerNotificationDevice, unregisterNotificationDevice } from "./notifications/deviceRegistry.js";
export { dispatchScheduledPushNotifications } from "./notifications/scheduledPushDispatch.js";
export { refreshLeaderboardSnapshots } from "./leaderboard/monthlyLeaderboard.js";
export { leaderboardAdminCommandCreated } from "./leaderboard/leaderboardAdminCommand.js";
export { moderationCommandCreated } from "./moderation/moderationCommand.js";
export { reportCreated } from "./moderation/reportAutomation.js";
export { escalateStaleReports } from "./moderation/staleReportSweep.js";
export { errorGroupWritten } from "./errors/errorGroupNotifications.js";
export { refreshStreakStatus } from "./progression/refreshStreakStatus.js";
export { expireSubscriptions } from "./progression/subscriptionExpirySchedule.js";
export { publishActivityToFeed } from "./feed/publish/callable.js";
export { readFeedThumbnail } from "./feed/thumbnail/callable.js";
export { getFeedAuthorLevels } from "./feed/authorLevels/callable.js";
export { reportFeedPost, deleteFeedPost, cleanupDeletedFeedActivity } from "./feed/lifecycle/functions.js";
export {
  feedLikeCreated,
  feedLikeDeleted,
  feedCommentCreated,
  feedCommentUpdated,
  feedCommentDeleted,
} from "./feed/engagement/engagement.js";
export {
  getChallengeCatalog,
  createChallengeLobby,
  inviteChallengeFriends,
  respondToChallengeInvitation,
  withdrawFromChallengeLobby,
  cancelChallengeLobby,
  startChallenge,
  getActiveChallenge,
  getChallengeInvitations,
  leaveChallenge,
  abandonChallenge,
} from "./challenge/callable.js";
export { settleChallengeDeadlines } from "./challenge/challengeSettlementSchedule.js";
export { challengeSubscriptionChanged } from "./challenge/challengePremiumLapseTrigger.js";
export {
  checkNicknameAvailability,
  upsertNickname,
  searchFriends,
  sendFriendRequest,
  cancelFriendRequest,
  respondToFriendRequest,
  removeFriend,
  blockUser,
  unblockUser,
  migrateUnicodeNicknameClaims,
} from "./friends/callable.js";
export { getFriendLevels } from "./friends/friendLevels/callable.js";
export { getRunnerPublicProfile } from "./profile/publicProfile/callable.js";
export { requestAccountDeletion } from "./account/requestAccountDeletion.js";
export { accountDeletionCommandCreated } from "./account/accountDeletionCommand.js";
export { setProfileAvatar, clearProfileAvatar } from "./profile/avatar/callable.js";
