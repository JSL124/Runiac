#!/usr/bin/env node
// avatar-path-contract-drift.mjs
//
// What this protects:
//   website/src/lib/avatarPaths.ts is a hand-maintained, verbatim mirror of
//   the avatar object-path/URL contract owned by
//   functions/src/profile/avatar/avatarPaths.ts. That module is the single
//   choke point that decides what counts as a valid avatar Storage object
//   path and a valid avatar download URL. The Cloud Function and the admin
//   console's takedown path both eventually pass a stored object path to a
//   Storage delete, and the admin console's Admin SDK bypasses Storage
//   security rules entirely — so if the two files silently drift, the admin
//   console could validate (or fail to reject) a path the backend would
//   treat differently, and a poisoned/buggy path could delete an unrelated
//   object (feed-thumbnail-staging/, feed-thumbnails/, share-cards/, or
//   project-documents/ all live in the same bucket; see storage.rules).
//   Nothing in the type system catches that drift because the two files
//   intentionally have no import relationship (the admin console must not
//   depend on Cloud Functions runtime code).
//
//   This script is a zero-dependency, Node-builtins-only text-level check
//   that extracts the shared exports from both files, normalizes away
//   comment/formatting differences, and diffs what's left. It runs from
//   Governance CI via tests/governance/avatar_path_contract_drift_test.sh.
//
// What to do when it fails:
//   Update BOTH files so the reported block matches again. Do not "fix" the
//   check by only touching one side, and do not silence a real mismatch by
//   loosening the normalizer. If a mismatch is intentional (a real contract
//   change), the change belongs in
//   functions/src/profile/avatar/avatarPaths.ts first (it is the source of
//   truth), then must be mirrored into website/src/lib/avatarPaths.ts in the
//   same change.
//
// Usage: node tests/cross-system/avatar-path-contract-drift.mjs
// Exit 0 = the two files agree on every compared block. Exit 1 = drift (or a
// block/export is missing on one side).

import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..", "..");

const FUNCTIONS_FILE = path.join(repoRoot, "functions/src/profile/avatar/avatarPaths.ts");
const WEBSITE_FILE = path.join(repoRoot, "website/src/lib/avatarPaths.ts");
const FUNCTIONS_LABEL = "functions/src/profile/avatar/avatarPaths.ts";
const WEBSITE_LABEL = "website/src/lib/avatarPaths.ts";

// The fixed set of exports both files are documented to keep in sync.
const FIXED_BLOCKS = [
  { name: "AVATAR_OBJECT_PATH_PATTERN", kind: "const" },
  { name: "isAvatarObjectPath", kind: "function" },
  { name: "newAvatarObjectPath", kind: "function" },
  { name: "AVATAR_STAGING_PATH_PATTERN", kind: "const" },
  { name: "isOwnedAvatarStagingPath", kind: "function" },
  { name: "buildAvatarDownloadUrl", kind: "function" },
  { name: "resolveProfileAvatarUrl", kind: "function" },
  { name: "avatarObjectPathFromUrl", kind: "function" },
];

function readText(filePath) {
  return readFileSync(filePath, "utf8");
}

function findMatchingIndex(text, openIndex, openChar, closeChar) {
  let depth = 0;
  for (let i = openIndex; i < text.length; i += 1) {
    const char = text[i];
    if (char === openChar) {
      depth += 1;
    } else if (char === closeChar) {
      depth -= 1;
      if (depth === 0) {
        return i;
      }
    }
  }
  throw new Error(
    `unbalanced '${openChar}'/'${closeChar}' starting at index ${openIndex} while extracting a block`,
  );
}

/**
 * Finds the index just past the first top-level ';' at or after `start`
 * (depth 0 across "(){}[]"). Used to extract a `export const NAME = <expr>;`
 * declaration regardless of whether <expr> is an object literal, a regex
 * literal, or any other expression shape.
 */
function findStatementEnd(text, start) {
  let depth = 0;
  for (let i = start; i < text.length; i += 1) {
    const char = text[i];
    if (char === "(" || char === "{" || char === "[") {
      depth += 1;
    } else if (char === ")" || char === "}" || char === "]") {
      depth -= 1;
    } else if (char === ";" && depth === 0) {
      return i + 1;
    }
  }
  throw new Error(`no top-level ';' found starting at index ${start} while extracting a block`);
}

/**
 * Extracts the source text of `export const NAME = <expr>;` or
 * `export function NAME(...) { ... }` from `text`. Returns null if the
 * declaration isn't present.
 */
function extractExport(text, name, kind) {
  const declRe = new RegExp(`export (?:const|function) ${escapeRegExp(name)}\\b`);
  const match = declRe.exec(text);
  if (!match) {
    return null;
  }

  const start = match.index;

  if (kind === "const") {
    const eqIndex = text.indexOf("=", start);
    const end = findStatementEnd(text, eqIndex);
    return text.slice(start, end);
  }

  // kind === "function": skip the parameter list, then brace-match the body.
  const parenIndex = text.indexOf("(", start);
  const parenEnd = findMatchingIndex(text, parenIndex, "(", ")");
  const braceIndex = text.indexOf("{", parenEnd);
  const braceEnd = findMatchingIndex(text, braceIndex, "{", "}");
  return text.slice(start, braceEnd + 1);
}

function escapeRegExp(literal) {
  return literal.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Normalizes a source block so that comment wording and line-wrapping
 * differences disappear, while preserving every meaningful token (numbers,
 * identifiers, operators, string/regex/template literals). Steps:
 *   1. Strip /* block *\/ and // line comments.
 *   2. Collapse all whitespace runs (including newlines) to a single space.
 *   3. Drop trailing commas before a closing `}`, `]`, or `)`.
 *   4. Remove the space directly after `(` and directly before `)`, so that
 *      a wrapped `fn(\n  arg,\n)` and an unwrapped `fn(arg)` compare equal.
 */
function normalizeBlock(rawText) {
  let text = rawText;

  // Strip /* ... */ block comments (non-greedy, single or multi-line).
  text = text.replace(/\/\*[\s\S]*?\*\//g, " ");

  // Strip // line comments. None of the target blocks contain string/regex
  // literals with a literal "//" sequence, so a straightforward line-scan
  // is safe here.
  text = text.replace(/\/\/[^\n]*/g, "");

  // Collapse whitespace runs to a single space.
  text = text.replace(/\s+/g, " ").trim();

  // Drop a trailing comma immediately before a closing bracket.
  text = text.replace(/,\s*([}\]\)])/g, "$1");

  // Remove the space right after "(" and right before ")".
  text = text.replace(/\(\s+/g, "(");
  text = text.replace(/\s+\)/g, ")");

  return text;
}

function firstDivergence(a, b) {
  const length = Math.min(a.length, b.length);
  for (let i = 0; i < length; i += 1) {
    if (a[i] !== b[i]) {
      return i;
    }
  }
  if (a.length !== b.length) {
    return length;
  }
  return -1;
}

function contextWindow(text, index, radius = 60) {
  const start = Math.max(0, index - radius);
  const end = Math.min(text.length, index + radius);
  const prefix = start > 0 ? "…" : "";
  const suffix = end < text.length ? "…" : "";
  return `${prefix}${text.slice(start, end)}${suffix}`;
}

function discoverExports(text) {
  const kindByName = new Map();
  const constRe = /export const ([A-Za-z_$][A-Za-z0-9_$]*)\b/g;
  const funcRe = /export function ([A-Za-z_$][A-Za-z0-9_$]*)\b/g;

  let match;
  while ((match = constRe.exec(text)) !== null) {
    kindByName.set(match[1], "const");
  }
  while ((match = funcRe.exec(text)) !== null) {
    kindByName.set(match[1], "function");
  }
  return kindByName;
}

function main() {
  // The admin console lives in a SEPARATE git repository that merely happens
  // to sit at website/ in a local checkout. Hosted CI clones only this
  // repository, so the mirror is genuinely absent there and reading it would
  // crash. Report the skip loudly rather than pretending the contract was
  // verified: this check is a local/dev guard, and the mirror's own
  // repository is responsible for its side.
  if (!existsSync(WEBSITE_FILE)) {
    console.log(
      `SKIP: avatar path contract not compared — ${WEBSITE_LABEL} is not present. ` +
        "The admin console is a separate repository; this check only runs where both are checked out.",
    );
    return 0;
  }

  const functionsText = readText(FUNCTIONS_FILE);
  const websiteText = readText(WEBSITE_FILE);

  const mismatches = [];

  // 1. Catch an export that exists on only one side (e.g. a new helper added
  //    to one file but never mirrored).
  const discoveredFunctions = discoverExports(functionsText);
  const discoveredWebsite = discoverExports(websiteText);

  for (const name of discoveredFunctions.keys()) {
    if (!discoveredWebsite.has(name)) {
      mismatches.push(
        `export '${name}' found in ${FUNCTIONS_LABEL} but missing from ${WEBSITE_LABEL}.`,
      );
    }
  }
  for (const name of discoveredWebsite.keys()) {
    if (!discoveredFunctions.has(name)) {
      mismatches.push(
        `export '${name}' found in ${WEBSITE_LABEL} but missing from ${FUNCTIONS_LABEL}.`,
      );
    }
  }

  // 2. Build the full comparison set: the fixed contract blocks, plus any
  //    other export discovered symmetrically on both sides (so a helper
  //    added to both files is still compared, not silently skipped).
  const fixedNames = new Set(FIXED_BLOCKS.map((block) => block.name));
  const blocksToCompare = [...FIXED_BLOCKS];

  for (const [name, kind] of discoveredFunctions) {
    if (fixedNames.has(name)) {
      continue;
    }
    if (discoveredWebsite.has(name)) {
      blocksToCompare.push({ name, kind });
    }
  }

  // 3. Extract, normalize, and compare each block.
  const compared = [];

  for (const { name, kind } of blocksToCompare) {
    const functionsRaw = extractExport(functionsText, name, kind);
    const websiteRaw = extractExport(websiteText, name, kind);

    if (functionsRaw === null && websiteRaw === null) {
      mismatches.push(`block '${name}' not found in either file.`);
      continue;
    }
    if (functionsRaw === null) {
      mismatches.push(`block '${name}' is missing from ${FUNCTIONS_LABEL}.`);
      continue;
    }
    if (websiteRaw === null) {
      mismatches.push(`block '${name}' is missing from ${WEBSITE_LABEL}.`);
      continue;
    }

    const functionsNormalized = normalizeBlock(functionsRaw);
    const websiteNormalized = normalizeBlock(websiteRaw);

    if (functionsNormalized === websiteNormalized) {
      compared.push(name);
      continue;
    }

    const diffIndex = firstDivergence(functionsNormalized, websiteNormalized);
    const functionsContext = contextWindow(functionsNormalized, diffIndex);
    const websiteContext = contextWindow(websiteNormalized, diffIndex);

    mismatches.push(
      [
        `block '${name}' differs between the two files (first divergence near normalized offset ${diffIndex}):`,
        `  ${FUNCTIONS_LABEL}:`,
        `    ${functionsContext}`,
        `  ${WEBSITE_LABEL}:`,
        `    ${websiteContext}`,
      ].join("\n"),
    );
  }

  if (mismatches.length > 0) {
    console.error("FAIL: avatar path contract drift detected between:");
    console.error(`  - ${FUNCTIONS_LABEL} (source of truth)`);
    console.error(`  - ${WEBSITE_LABEL} (admin console copy)`);
    console.error("");
    for (const mismatch of mismatches) {
      console.error(mismatch);
      console.error("");
    }
    console.error("Update BOTH files so the reported block(s) match again.");
    process.exit(1);
  }

  console.log(`PASS: avatar path contract in sync (compared: ${compared.join(", ")})`);
  process.exit(0);
}

main();
