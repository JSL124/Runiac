import assert from "node:assert/strict";
import { describe, it } from "node:test";
import * as productionFunctions from "../src/index.js";

/**
 * Every function deployed from the production entrypoint.
 *
 * This is a deliberate maintenance burden: an export added here is a publicly
 * deployed callable/trigger, so adding one must be a conscious, reviewed act
 * rather than a side effect. Adding a Function without updating this list is
 * expected to fail the suite.
 *
 * Kept in `feedCallableSurface.test.ts` for historical reasons — the Feed
 * capsule introduced the guard — but it covers the whole entrypoint, not just
 * Feed. The Feed-owned subset is asserted separately below.
 */
const expectedExports = [
  "abandonChallenge",
  // Firestore trigger running the account-deletion erase fan-out. Separate from
  // requestAccountDeletion because the fan-out is unbounded and cannot be
  // guaranteed to fit a callable's execution budget.
  "accountDeletionCommandCreated",
  "activityFeedbackAgent",
  "blockUser",
  "cancelChallengeLobby",
  // users/{uid} update trigger opening/clearing the challenge premium-lapse
  // grace hold. Deploying it is what makes an admin-console downgrade visible
  // to the challenge system at all.
  "challengeSubscriptionChanged",
  "cancelFriendRequest",
  "checkNicknameAvailability",
  "cleanupDeletedFeedActivity",
  "clearProfileAvatar",
  "completeCoolDown",
  "completeRun",
  "confirmNewsletterSubscription",
  "createChallengeLobby",
  "deleteFeedPost",
  "dispatchScheduledPushNotifications",
  "errorGroupWritten",
  "escalateStaleReports",
  "expireSubscriptions",
  "feedCommentCreated",
  "feedCommentDeleted",
  "feedCommentUpdated",
  "feedLikeCreated",
  "feedLikeDeleted",
  "getActiveChallenge",
  "getChallengeCatalog",
  "getChallengeInvitations",
  "getFeedAuthorLevels",
  "getFriendLevels",
  "getRunnerPublicProfile",
  "homeGuideAgent",
  "homeGuideConsent",
  "inviteChallengeFriends",
  "leaderboardAdminCommandCreated",
  "leaveChallenge",
  "migrateUnicodeNicknameClaims",
  "moderationCommandCreated",
  "newsletterCampaignQueued",
  "publishActivityToFeed",
  "readFeedThumbnail",
  "refreshLeaderboardSnapshots",
  "refreshStreakStatus",
  "registerNotificationDevice",
  "removeFriend",
  "reportAppError",
  "reportCreated",
  "reportFeedPost",
  // Stage A of account deletion: locks the account out, releases the nickname,
  // and enqueues the erase. Store policy (Apple 5.1.1(v), Google Play data
  // deletion) requires this path to exist inside the app.
  "requestAccountDeletion",
  "respondToChallengeInvitation",
  "respondToFriendRequest",
  "searchFriends",
  "sendFriendRequest",
  "setProfileAvatar",
  "settleChallengeDeadlines",
  "startChallenge",
  "submitFeedback",
  "subscribeNewsletter",
  "sweepUnconfirmedSubscribers",
  "unblockUser",
  "unregisterNotificationDevice",
  "unsubscribeNewsletter",
  "upsertNickname",
  "withdrawFromChallengeLobby",
  "workoutBriefingAgent",
] as const;

const feedExports = [
  "cleanupDeletedFeedActivity",
  "deleteFeedPost",
  "feedCommentCreated",
  "feedCommentDeleted",
  "feedCommentUpdated",
  "feedLikeCreated",
  "feedLikeDeleted",
  "getFeedAuthorLevels",
  "publishActivityToFeed",
  "readFeedThumbnail",
  "reportFeedPost",
] as const;

describe("Feed callable production surface", () => {
  it("exports exactly the production Feed callables and triggers once", () => {
    assert.deepEqual(Object.keys(productionFunctions).sort(), [...expectedExports].sort());
    assert.deepEqual(
      Object.keys(productionFunctions).filter(isFeedExport).sort(),
      [...feedExports].sort(),
    );
  });

  it("does not leak Feed fixture or core helpers through the production entrypoint", () => {
    for (const name of [
      "applySyntheticFeedFixture",
      "assertFeedFixtureEnvironment",
      "createAuthorLevelsPorts",
      "createFeedEngagementHandlers",
      "createPublishPorts",
      "createThumbnailPorts",
      "createRunnerPublicProfilePorts",
      "getFeedAuthorLevelsCore",
      "publishFeedActivity",
      "readFeedThumbnailCore",
      "syntheticFeedFixture",
    ]) {
      assert.equal(name in productionFunctions, false, `${name} must not be a deployed Function export`);
    }
  });
});

function isFeedExport(name: string): name is (typeof feedExports)[number] {
  return feedExports.some((feedExport) => feedExport === name);
}
