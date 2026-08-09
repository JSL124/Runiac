import { HttpsError } from "firebase-functions/v2/https";
import type { FeedRelationshipCheckInput, FeedRelationshipDecision } from "../relationship.js";
import { evaluateFeedRelationship } from "../relationship.js";
import { resolveProfileLevelDisplay, type ProfileLevelDisplay } from "../../progression/profileLevelDisplay.js";
import { resolveProfileIdentityDisplay, type ProfileIdentityDisplay } from "../../profile/profileIdentityDisplay.js";
import type { AvatarUrlContext } from "../../profile/avatar/avatarPaths.js";
import { NULL_AVATAR_URL_CONTEXT } from "../../profile/avatar/avatarUrlContextDefaults.js";

export type FeedAuthorLevelsRequest = { readonly auth?: { readonly uid: string }; readonly data: unknown };

/**
 * One author's CURRENT display identity and level, as the viewer's Feed should
 * render them right now.
 *
 * A Feed post and a Feed comment both freeze `authorDisplayName`,
 * `authorAvatarInitials`, and `authorLevelLabel` at write time, and
 * `feedPosts` is closed to every client write, so a renamed runner would keep
 * appearing under their old name on every earlier post. This is what the
 * client overlays on top of those stored values. `avatarUrl` (via
 * `ProfileIdentityDisplay`) rides along the same overlay for the same reason:
 * a replaced avatar must show up on a runner's old posts too.
 *
 * The callable id stays `getFeedAuthorLevels` because it is already deployed
 * and older app builds still call it; only its result grew.
 */
export type FeedAuthorLevel = ProfileLevelDisplay & ProfileIdentityDisplay;
export type FeedAuthorLevelsResult = { readonly levels: Readonly<Record<string, FeedAuthorLevel>> };
export interface FeedAuthorLevelsPorts {
  relationshipFor(viewerUid: string, authorUid: string): Promise<FeedRelationshipCheckInput>;
  readProfiles(uids: readonly string[]): Promise<readonly (Readonly<Record<string, unknown>> | undefined)[]>;
  /**
   * `status` and `authorUid` of one `feedPosts/{postId}`, or `undefined` when
   * no such post exists. Only used by the post-scoped form below.
   */
  readPost?(postId: string): Promise<FeedPostVisibility | undefined>;
  /**
   * Which of [uids] actually authored a comment on `feedPosts/{postId}`.
   * Membership is proven server-side; the caller's claim is never trusted.
   */
  commentAuthorsAmong?(postId: string, uids: readonly string[]): Promise<readonly string[]>;
}

export type FeedPostVisibility = { readonly status: string; readonly authorUid: string };

const MAX_UIDS = 50;

export async function getFeedAuthorLevels(
  request: FeedAuthorLevelsRequest,
  ports: FeedAuthorLevelsPorts,
  // Injected by the callable layer (see profile/avatar/context.ts); defaults
  // to a context that can never match a real avatar URL, so an omitted
  // context still fails closed to avatarUrl: "".
  avatarContext: AvatarUrlContext = NULL_AVATAR_URL_CONTEXT,
): Promise<FeedAuthorLevelsResult> {
  const uid = request.auth?.uid;
  if (uid === undefined || uid.length === 0) throw new HttpsError("unauthenticated", "Authentication is required.");
  const parsed = parseRequest(request.data);
  if (parsed === undefined) throw new HttpsError("invalid-argument", "Invalid author levels request.");
  const unique = [...new Set(parsed.uids)];
  if (unique.length > MAX_UIDS) throw new HttpsError("invalid-argument", `At most ${MAX_UIDS} uids may be requested.`);
  if (unique.length === 0) return { levels: {} };
  const decisions = new Map<string, FeedRelationshipDecision>();
  await Promise.all(unique.map(async (authorUid) => {
    if (authorUid === uid) { decisions.set(authorUid, { kind: "allowed_owner" }); return; }
    decisions.set(authorUid, evaluateFeedRelationship(await ports.relationshipFor(uid, authorUid)));
  }));
  const permitted = new Set(unique.filter((authorUid) => isAllowed(decisions.get(authorUid))));
  for (const authorUid of await postScopedGrants(uid, unique, decisions, permitted, parsed.postId, ports)) {
    permitted.add(authorUid);
  }
  if (permitted.size === 0) return { levels: {} };
  const resolvable = unique.filter((authorUid) => permitted.has(authorUid));
  const profiles = await ports.readProfiles(resolvable);
  const levels: Record<string, FeedAuthorLevel> = {};
  resolvable.forEach((authorUid, index) => {
    levels[authorUid] = { ...resolveProfileLevelDisplay(profiles[index]), ...resolveProfileIdentityDisplay(profiles[index], avatarContext) };
  });
  return { levels };
}

function isAllowed(decision: FeedRelationshipDecision | undefined): boolean {
  return decision?.kind === "allowed_owner" || decision?.kind === "allowed_friend";
}

/**
 * The uids a viewer may resolve because they are looking at ONE post they are
 * allowed to read, rather than because they are friends with each author.
 *
 * `firestore.rules` authorizes a comment through its POST — `canReadFeedPost`
 * checks the post author, not the commenter — so two runners who share a
 * friend but not each other still read each other's comments on that friend's
 * post. Without this grant their stored names are the only ones the Feed ever
 * shows, and the rename defect survives exactly there.
 *
 * The grant is deliberately narrow:
 *
 * - it returns the SAME three display fields (`displayName`, `avatarInitials`,
 *   level) the viewer can already read, frozen, on the comment document — only
 *   current instead of stale. It is not a new class of disclosure, and it
 *   still never returns a uid the caller did not already supply.
 * - the viewer must pass the same post-author check `canReadFeedPost` applies,
 *   against a post that actually exists and is `published`.
 * - the uid must be proven server-side to have commented on that post.
 * - a directional block still denies, which is STRICTER than the rules: they
 *   check blocks against the post author only, so a blocked runner's comment
 *   stays visible but their live identity is withheld here.
 */
async function postScopedGrants(
  viewerUid: string,
  unique: readonly string[],
  decisions: ReadonlyMap<string, FeedRelationshipDecision>,
  alreadyPermitted: ReadonlySet<string>,
  postId: string | undefined,
  ports: FeedAuthorLevelsPorts,
): Promise<readonly string[]> {
  if (postId === undefined || ports.readPost === undefined || ports.commentAuthorsAmong === undefined) return [];
  // A block is never relaxed by post scope; only a missing friendship is.
  const candidates = unique.filter((authorUid) => {
    if (alreadyPermitted.has(authorUid)) return false;
    const decision = decisions.get(authorUid);
    return decision?.kind === "denied" && decision.reason === "missing_reciprocal_friendship";
  });
  if (candidates.length === 0) return [];
  const post = await ports.readPost(postId);
  if (post === undefined || post.status !== "published") return [];
  const viewerMayReadPost = post.authorUid === viewerUid
    ? true
    : isAllowed(decisions.get(post.authorUid) ?? evaluateFeedRelationship(await ports.relationshipFor(viewerUid, post.authorUid)));
  if (!viewerMayReadPost) return [];
  return ports.commentAuthorsAmong(postId, candidates);
}

function parseRequest(raw: unknown): { readonly uids: readonly string[]; readonly postId?: string } | undefined {
  if (!isRecord(raw)) return undefined;
  const keys = Object.keys(raw).sort();
  const uidOnly = keys.length === 1 && keys[0] === "uids";
  const postScoped = keys.length === 2 && keys[0] === "postId" && keys[1] === "uids";
  if (!uidOnly && !postScoped) return undefined;
  const uids = raw["uids"];
  if (!Array.isArray(uids) || !uids.every(isNonEmptyString)) return undefined;
  if (uidOnly) return { uids };
  const postId = safeIdentifier(raw["postId"]);
  return postId === undefined ? undefined : { uids, postId };
}

function safeIdentifier(value: unknown): string | undefined {
  if (typeof value !== "string" || value.length === 0 || value.length > 256) return undefined;
  if (value.includes("/") || value.includes("..") || /[\u0000-\u001F\u007F]/u.test(value)) return undefined;
  return value;
}
function isNonEmptyString(value: unknown): value is string { return typeof value === "string" && value.length > 0; }
function isRecord(value: unknown): value is Readonly<Record<string, unknown>> { return typeof value === "object" && value !== null && !Array.isArray(value); }
