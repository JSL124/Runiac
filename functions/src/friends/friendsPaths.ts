import { createHash } from "node:crypto";

import type { Firestore } from "firebase-admin/firestore";

export function profileRef(firestore: Firestore, uid: string) {
  return firestore.doc(`userProfiles/${uid}`);
}

export function claimRef(firestore: Firestore, indexKey: string) {
  return firestore.doc(`nicknameClaims/${indexKey}`);
}

export function friendRef(firestore: Firestore, uid: string, friendUid: string) {
  return firestore.doc(`users/${uid}/friends/${friendUid}`);
}

export function requestRef(firestore: Firestore, uid: string, otherUid: string) {
  return firestore.doc(`users/${uid}/friendRequests/${otherUid}`);
}

export function blockRef(firestore: Firestore, uid: string, targetUid: string) {
  return firestore.doc(`users/${uid}/blockedUsers/${targetUid}`);
}

export function rateRef(firestore: Firestore, uid: string) {
  return firestore.doc(`friendRateLimits/${uid}`);
}

export function cooldownRef(firestore: Firestore, firstUid: string, secondUid: string) {
  const [left, right] = [firstUid, secondUid].sort();
  const key = createHash("sha256").update(`${left}\u0000${right}`, "utf8").digest("hex");
  return firestore.doc(`friendCooldowns/p1_${key}`);
}

export function safeDocumentId(value: string): boolean {
  return value.length > 0 && !value.includes("/") && !value.includes("..") && !/[\u0000-\u001F\u007F]/u.test(value);
}
