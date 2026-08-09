// Stage B and C of account deletion: the erase fan-out, and the Auth delete
// that finalizes it.
//
// Every step is idempotent, because this runs from a Firestore trigger that may
// be redelivered and because a step that exceeds the execution budget has to be
// safe to resume. Idempotency here is structural rather than guarded: deleting
// an already-deleted document is a no-op, and every query is "find rows still
// carrying this uid", which returns nothing once the step has converged. The
// `completedSteps` cursor is therefore an optimisation that avoids re-scanning,
// not a correctness requirement — which matters, because a crash between a
// committed batch and a cursor write must not corrupt anything.
//
// Ordering is defined by ACCOUNT_DELETION_STEPS, not by this file. See the
// inventory module for why the order is load-bearing.

import { FieldPath, FieldValue, type Firestore, type Query } from "firebase-admin/firestore";
import type { Auth } from "firebase-admin/auth";
import type { Storage } from "firebase-admin/storage";

import { beginFeedPostCleanup } from "../feed/lifecycle/core.js";
import { cleanupFeedPost } from "../feed/cleanup.js";
import { firebaseLifecyclePort } from "../feed/lifecycle/firebasePort.js";
import { exitChallengeForAccountDeletion } from "./accountChallengeExit.js";
import {
  ACCOUNT_DELETION_STEPS,
  DELETED_USER_SENTINEL,
  accountStoragePrefixes,
  type DeletionStep,
} from "./accountDeletionInventory.js";

// Firestore caps a batch at 500 writes. 300 leaves headroom for the occasional
// multi-write step and keeps a single commit well inside the request budget.
const BATCH_SIZE = 300;

// Upper bound on documents examined by the two steps that cannot be reduced to
// a uid query (friendCooldowns, keyed by a hash of the uid pair; errorGroups,
// whose reporters marker is keyed by uid in a subcollection). Both collections
// are operationally small. If either ever grows past this, the scan reports
// `truncated` rather than silently covering part of it.
const SCAN_LIMIT = 2000;

export type AccountDeletionDependencies = {
  readonly firestore: Firestore;
  readonly storage: Storage;
  readonly auth: Auth;
};

export type AccountDeletionStepOutcome = {
  readonly stepId: string;
  readonly deletedCount: number;
  readonly truncated: boolean;
};

export type AccountDeletionResult = {
  readonly uid: string;
  readonly completedSteps: readonly string[];
  readonly outcomes: readonly AccountDeletionStepOutcome[];
};

export type AccountDeletionOptions = {
  // Steps already known to have converged, from a previous partial run.
  readonly completedSteps?: readonly string[];
  // Invoked after each step commits, so the caller can advance its cursor
  // without this module knowing where the cursor lives.
  readonly onStepCompleted?: (outcome: AccountDeletionStepOutcome) => Promise<void>;
};

/**
 * Runs the erase fan-out for `uid`, then deletes the Auth user.
 *
 * The caller is expected to have already locked the account (accountStatus
 * `deleting`, refresh tokens revoked, Auth user disabled). This function does
 * not re-assert that, deliberately: it must remain able to finish a deletion
 * whose lock stage partially failed.
 */
export async function runAccountDeletionFanOut(
  dependencies: AccountDeletionDependencies,
  uid: string,
  nowMs: number,
  options: AccountDeletionOptions = {},
): Promise<AccountDeletionResult> {
  const alreadyDone = new Set(options.completedSteps ?? []);
  const completedSteps: string[] = [...alreadyDone];
  const outcomes: AccountDeletionStepOutcome[] = [];

  // Collected by the `resolveAvatarObjects` step and consumed by `storage`.
  // The durable avatar object is the one asset whose path is discoverable only
  // from a document this fan-out later deletes.
  const resolvedStorageObjects: string[] = [];

  for (const step of ACCOUNT_DELETION_STEPS) {
    if (alreadyDone.has(step.id)) continue;

    const outcome = await runStep(dependencies, step, uid, nowMs, resolvedStorageObjects);
    outcomes.push(outcome);
    completedSteps.push(step.id);
    if (options.onStepCompleted !== undefined) {
      await options.onStepCompleted(outcome);
    }
  }

  return { uid, completedSteps, outcomes };
}

async function runStep(
  dependencies: AccountDeletionDependencies,
  step: DeletionStep,
  uid: string,
  nowMs: number,
  resolvedStorageObjects: string[],
): Promise<AccountDeletionStepOutcome> {
  const { firestore } = dependencies;

  switch (step.kind) {
    case "challengeExit": {
      const result = await exitChallengeForAccountDeletion(firestore, uid, nowMs);
      return outcome(step.id, result.kind === "none" ? 0 : 1);
    }

    case "resolveAvatarObjects": {
      const profile = await firestore.doc(`userProfiles/${uid}`).get();
      const data = profile.data();
      for (const key of ["avatarObjectPath", "avatarPreviousObjectPath"]) {
        const value = data?.[key];
        if (typeof value === "string" && value.length > 0) {
          resolvedStorageObjects.push(value);
        }
      }
      return outcome(step.id, resolvedStorageObjects.length);
    }

    case "feedPosts": {
      return deleteAuthoredFeedPosts(firestore, uid, step.id);
    }

    case "ownerQuery": {
      let deleted = 0;
      for (const field of step.fields) {
        deleted += await deleteQueryInBatches(
          firestore,
          firestore.collection(step.collection).where(field, "==", uid),
        );
      }
      return outcome(step.id, deleted);
    }

    case "documentIdPrefix": {
      // Ids are `{uid}_{suffix}`. Within a single collection, documentId()
      // range comparisons order lexicographically by id, so the half-open
      // range [`{uid}_`, successor) selects exactly this runner's documents
      // and nothing else.
      const deleted = await deleteQueryInBatches(
        firestore,
        firestore
          .collection(step.collection)
          .where(FieldPath.documentId(), ">=", `${uid}_`)
          .where(FieldPath.documentId(), "<", prefixUpperBound(`${uid}_`)),
      );
      return outcome(step.id, deleted);
    }

    case "collectionGroup": {
      let deleted = 0;
      for (const group of step.groups) {
        deleted += await deleteQueryInBatches(
          firestore,
          firestore.collectionGroup(group).where(step.field, "==", uid),
        );
      }
      return outcome(step.id, deleted);
    }

    case "uidDocument": {
      let deleted = 0;
      const reference = firestore.doc(`${step.collection}/${uid}`);
      for (const subcollection of step.subcollections ?? []) {
        deleted += await deleteQueryInBatches(firestore, reference.collection(subcollection));
      }
      // Delete the parent AFTER its subcollections: a crash in between leaves an
      // orphan subcollection that is still reachable from this same path on
      // replay, whereas deleting the parent first would leave one that is not.
      await reference.delete();
      return outcome(step.id, deleted + 1);
    }

    case "anonymize": {
      return anonymizeCollection(firestore, step, uid);
    }

    case "uidMarkerInSubcollection": {
      return deleteUidMarkers(firestore, step.parentCollection, step.subcollection, uid, step.id);
    }

    case "friendCooldowns": {
      return stripFriendCooldowns(firestore, uid, step.id);
    }

    case "storage": {
      return deleteStorageObjects(dependencies.storage, uid, resolvedStorageObjects, step.id);
    }

    case "authUser": {
      await deleteAuthUser(dependencies.auth, uid);
      return outcome(step.id, 1);
    }

    default:
      return assertNever(step);
  }
}

// ---------------------------------------------------------------------------
// Step implementations
// ---------------------------------------------------------------------------

// Authored posts go through the feed system's own cleanup pair rather than a
// raw delete, so likes, comments, Storage thumbnails, and the hidden markers
// other users hold all go with them. `beginFeedPostCleanup` treats an undefined
// ownerUid as the system/admin override path — the same composition
// `moderationCommand.ts` uses — which is correct here: the owner is being
// erased, so there is no caller to check ownership against.
async function deleteAuthoredFeedPosts(
  firestore: Firestore,
  uid: string,
  stepId: string,
): Promise<AccountDeletionStepOutcome> {
  const port = firebaseLifecyclePort(firestore);
  let deleted = 0;

  for (;;) {
    const snapshot = await firestore
      .collection("feedPosts")
      .where("authorUid", "==", uid)
      .limit(BATCH_SIZE)
      .get();
    if (snapshot.empty) break;

    for (const document of snapshot.docs) {
      const beginning = await beginFeedPostCleanup({ port, postId: document.id });
      if (beginning.kind === "ready") {
        await cleanupFeedPost(port, beginning.post);
      }
      deleted += 1;
    }

    if (snapshot.size < BATCH_SIZE) break;
  }

  return outcome(stepId, deleted);
}

async function anonymizeCollection(
  firestore: Firestore,
  step: Extract<DeletionStep, { kind: "anonymize" }>,
  uid: string,
): Promise<AccountDeletionStepOutcome> {
  let updated = 0;

  for (const spec of step.fields) {
    for (;;) {
      const snapshot = await firestore
        .collection(step.collection)
        .where(spec.field, "==", uid)
        .limit(BATCH_SIZE)
        .get();
      if (snapshot.empty) break;

      const batch = firestore.batch();
      let batched = 0;
      for (const document of snapshot.docs) {
        if (
          spec.onlyWhen !== undefined &&
          document.get(spec.onlyWhen.field) !== spec.onlyWhen.equals
        ) {
          continue;
        }
        batch.update(document.ref, { [spec.field]: DELETED_USER_SENTINEL });
        batched += 1;
      }

      if (batched === 0) {
        // Every row in this page was excluded by `onlyWhen`. The query filters
        // on the uid, so those rows will be returned again forever — stop
        // rather than spin. They are correctly left alone: a report whose
        // targetId equals this uid but whose targetType is not 'user' is not
        // about this runner at all.
        break;
      }

      await batch.commit();
      updated += batched;
      if (snapshot.size < BATCH_SIZE) break;
    }
  }

  return outcome(step.id, updated);
}

// errorGroups/{groupId}/reporters/{uid}: a bounded scan of the parent
// collection, deleting the one marker under each group that this runner filed.
async function deleteUidMarkers(
  firestore: Firestore,
  parentCollection: string,
  subcollection: string,
  uid: string,
  stepId: string,
): Promise<AccountDeletionStepOutcome> {
  const parents = await firestore.collection(parentCollection).limit(SCAN_LIMIT + 1).get();
  const truncated = parents.size > SCAN_LIMIT;
  const scanned = truncated ? parents.docs.slice(0, SCAN_LIMIT) : parents.docs;

  let deleted = 0;
  for (let index = 0; index < scanned.length; index += BATCH_SIZE) {
    const slice = scanned.slice(index, index + BATCH_SIZE);
    const references = slice.map((parent) => parent.ref.collection(subcollection).doc(uid));
    const markers = await firestore.getAll(...references);
    const present = markers.filter((marker) => marker.exists);
    if (present.length === 0) continue;

    const batch = firestore.batch();
    for (const marker of present) batch.delete(marker.ref);
    await batch.commit();
    deleted += present.length;
  }

  return { stepId, deletedCount: deleted, truncated };
}

// friendCooldowns/p1_{sha256(pair)} cannot be queried by uid: the document id is
// a hash of the uid PAIR and the uid appears only as a MAP KEY inside
// `directionalCooldownUntilByUid`. A bounded scan is the only way to reach it.
// The collection is small and self-expiring, so this stays cheap.
async function stripFriendCooldowns(
  firestore: Firestore,
  uid: string,
  stepId: string,
): Promise<AccountDeletionStepOutcome> {
  const snapshot = await firestore.collection("friendCooldowns").limit(SCAN_LIMIT + 1).get();
  const truncated = snapshot.size > SCAN_LIMIT;
  const scanned = truncated ? snapshot.docs.slice(0, SCAN_LIMIT) : snapshot.docs;

  const affected = scanned.filter((document) => {
    const map = document.get("directionalCooldownUntilByUid");
    const hasKey = isRecord(map) && Object.prototype.hasOwnProperty.call(map, uid);
    return hasKey || document.get("lastOutcomeSenderUid") === uid;
  });

  let updated = 0;
  for (let index = 0; index < affected.length; index += BATCH_SIZE) {
    const batch = firestore.batch();
    for (const document of affected.slice(index, index + BATCH_SIZE)) {
      const update: Record<string, unknown> = {
        [`directionalCooldownUntilByUid.${uid}`]: FieldValue.delete(),
      };
      if (document.get("lastOutcomeSenderUid") === uid) {
        update["lastOutcomeSenderUid"] = DELETED_USER_SENTINEL;
      }
      batch.update(document.ref, update);
      updated += 1;
    }
    await batch.commit();
  }

  return { stepId, deletedCount: updated, truncated };
}

async function deleteStorageObjects(
  storage: Storage,
  uid: string,
  resolvedObjects: readonly string[],
  stepId: string,
): Promise<AccountDeletionStepOutcome> {
  const bucket = storage.bucket();
  let deleted = 0;

  for (const prefix of accountStoragePrefixes(uid)) {
    // Listed rather than blind-deleted so the outcome carries a real object
    // count. `deleteFiles` would be one call, but it reports nothing, and an
    // erase step that cannot say how much it erased is not auditable.
    const [files] = await bucket.getFiles({ prefix });
    for (const file of files) {
      await file.delete({ ignoreNotFound: true });
      deleted += 1;
    }
  }

  for (const objectPath of resolvedObjects) {
    // `ignoreNotFound` keeps a replay — or an avatar already cleared through
    // clearProfileAvatar — from failing the whole step.
    await bucket.file(objectPath).delete({ ignoreNotFound: true });
    deleted += 1;
  }

  return outcome(stepId, deleted);
}

async function deleteAuthUser(auth: Auth, uid: string): Promise<void> {
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    // Already gone: a redelivered trigger reaching the last step again is the
    // expected way to see this, and it means the deletion succeeded.
    if (isAuthUserNotFound(error)) return;
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function deleteQueryInBatches(firestore: Firestore, query: Query): Promise<number> {
  let deleted = 0;
  for (;;) {
    const snapshot = await query.limit(BATCH_SIZE).get();
    if (snapshot.empty) return deleted;

    const batch = firestore.batch();
    for (const document of snapshot.docs) batch.delete(document.ref);
    await batch.commit();
    deleted += snapshot.size;

    // A short page means the query is exhausted. A full page means there may be
    // more, and the next iteration re-runs the same query — which now returns
    // the rows that were behind the ones just deleted.
    if (snapshot.size < BATCH_SIZE) return deleted;
  }
}

// The smallest string strictly greater than every string starting with
// `prefix`: increment the final code unit. Used instead of the common
// `prefix + ''` trick because that one is only *probably* an upper bound
// — it fails for any id containing a code point above U+F8FF.
function prefixUpperBound(prefix: string): string {
  const lastIndex = prefix.length - 1;
  const next = String.fromCharCode(prefix.charCodeAt(lastIndex) + 1);
  return `${prefix.slice(0, lastIndex)}${next}`;
}

function outcome(stepId: string, deletedCount: number): AccountDeletionStepOutcome {
  return { stepId, deletedCount, truncated: false };
}

function isAuthUserNotFound(error: unknown): boolean {
  return isRecord(error) && error["code"] === "auth/user-not-found";
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function assertNever(value: never): never {
  throw new TypeError(`Unhandled account deletion step: ${JSON.stringify(value)}`);
}
