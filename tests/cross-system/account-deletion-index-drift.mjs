#!/usr/bin/env node
// account-deletion-index-drift.mjs
//
// What this protects:
//   Every `kind: "collectionGroup"` step in
//   functions/src/account/accountDeletionInventory.ts runs
//   `firestore.collectionGroup(group).where(field, "==", uid)` from
//   accountDeletionCore.ts. A collection-group equality query needs a
//   COLLECTION_GROUP-scoped single-field index, and Firestore does NOT create
//   one implicitly the way it does for collection-scoped queries. Without the
//   index the query throws FAILED_PRECONDITION at runtime.
//
//   That is not a recoverable inconvenience here. accountDeletionCommand.ts
//   disables the Auth user and revokes refresh tokens BEFORE the erase
//   fan-out runs, and a throwing step aborts the command at
//   `status: "failed"` with every later step unexecuted. The observed failure
//   (accountDeletionCommands/1tfcxmyohWTaWvAEol1hv7479HE2, 2026-08-05) left a
//   runner locked out of an account whose activities, run summaries,
//   progression events, and storage objects were all still present — the
//   exact opposite of what a deletion request promises, and a data-protection
//   problem rather than a bug report.
//
//   Nothing in the type system connects the two files: the inventory is
//   TypeScript, the index declaration is JSON consumed by
//   `firebase deploy --only firestore:indexes`. The original omission shipped
//   because `social-mirrors` reuses groups the nickname fanout had already
//   indexed, so three of the four collection-group steps worked and the gap
//   was invisible until a real deletion hit `feed-engagement` first.
//
// Scope and known limitation:
//   This checks the deletion inventory, which is the declarative list and the
//   only place a new collection-group sweep is expected to be added. It does
//   NOT scan for ad-hoc `firestore.collectionGroup(...)` calls elsewhere in
//   functions/src; those are few, hand-audited, and some build the group name
//   from a variable, which no text-level check can resolve. Adding a
//   collection-group query outside the inventory still requires declaring its
//   index by hand.
//
// What to do when it fails:
//   Add the missing entry to the `fieldOverrides` array in
//   firestore.indexes.json:
//
//     { "collectionGroup": "<group>", "fieldPath": "<field>",
//       "indexes": [{ "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" }] }
//
//   then deploy it with `firebase deploy --only firestore:indexes` and WAIT
//   for the build to finish before the fan-out can rely on it. Do not silence
//   this check by removing the step from the inventory unless the data it
//   erases genuinely no longer exists.
//
// Usage: node tests/cross-system/account-deletion-index-drift.mjs
// Exit 0 = every collection-group deletion step has a declared index.
// Exit 1 = at least one step would throw FAILED_PRECONDITION in production.

import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join, resolve } from "node:path";

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), "..", "..");
const INVENTORY = join(repoRoot, "functions/src/account/accountDeletionInventory.ts");
const INDEXES = join(repoRoot, "firestore.indexes.json");

function fail(message) {
  process.stdout.write(`FAIL account-deletion-index-drift: ${message}\n`);
  process.exit(1);
}

for (const path of [INVENTORY, INDEXES]) {
  if (!existsSync(path)) {
    fail(`missing required file ${path.slice(repoRoot.length + 1)}`);
  }
}

// Strip `//` line comments so prose between object keys cannot break the
// step matcher. Block comments are not used inside the steps array.
const inventorySource = readFileSync(INVENTORY, "utf8")
  .split("\n")
  .map((line) => line.replace(/^\s*\/\/.*$/, ""))
  .join("\n");

const STEP_PATTERN =
  /id:\s*"([^"]+)"\s*,\s*kind:\s*"collectionGroup"\s*,\s*groups:\s*\[([^\]]*)\]\s*,\s*field:\s*"([^"]+)"/g;

const requiredPairs = [];
for (const match of inventorySource.matchAll(STEP_PATTERN)) {
  const [, stepId, groupList, field] = match;
  const groups = [...groupList.matchAll(/"([^"]+)"/g)].map((group) => group[1]);
  if (groups.length === 0) {
    fail(`step "${stepId}" declares kind "collectionGroup" with no groups`);
  }
  for (const group of groups) {
    requiredPairs.push({ stepId, group, field });
  }
}

// A zero match means the inventory's shape changed and this check silently
// stopped protecting anything — louder than a false pass.
if (requiredPairs.length === 0) {
  fail(
    'found no `kind: "collectionGroup"` steps in accountDeletionInventory.ts; ' +
      "the step shape changed and this check needs updating",
  );
}

let indexesDocument;
try {
  indexesDocument = JSON.parse(readFileSync(INDEXES, "utf8"));
} catch (error) {
  fail(`firestore.indexes.json is not valid JSON: ${error.message}`);
}

const declared = new Set();
for (const override of indexesDocument.fieldOverrides ?? []) {
  const hasCollectionGroupScope = (override.indexes ?? []).some(
    (index) => index.queryScope === "COLLECTION_GROUP" && index.order === "ASCENDING",
  );
  if (hasCollectionGroupScope) {
    declared.add(`${override.collectionGroup} ${override.fieldPath}`);
  }
}

const missing = requiredPairs.filter(
  (pair) => !declared.has(`${pair.group} ${pair.field}`),
);

if (missing.length > 0) {
  const detail = missing
    .map(
      (pair) =>
        `  step "${pair.stepId}" queries collectionGroup("${pair.group}").where("${pair.field}") ` +
        "— no ASCENDING COLLECTION_GROUP fieldOverride declared",
    )
    .join("\n");
  fail(
    `${missing.length} account-deletion sweep(s) would throw FAILED_PRECONDITION:\n${detail}`,
  );
}

process.stdout.write(
  `PASS account-deletion-index-drift: ${requiredPairs.length} collection-group deletion ` +
    "queries all have a declared COLLECTION_GROUP index\n",
);
