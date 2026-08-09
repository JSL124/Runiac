#!/usr/bin/env node
// config-contract-drift.mjs
//
// What this protects:
//   website/src/lib/admin/config-validation.ts is a hand-maintained copy of
//   the backend config contract owned by functions/src/config/configLoader.ts
//   (DEFAULT_PROGRESSION_CONFIG, DEFAULT_LEADERBOARD_CONFIG,
//   DEFAULT_FEATURE_ACCESS_CONFIG, deepMerge, and the three validate*Config
//   functions). The admin console uses its copy to preview/validate config
//   edits before they are written to Firestore; Cloud Functions is the only
//   runtime that actually enforces the contract. If the two files silently
//   drift, the admin console can approve a config change that the backend
//   would reject (or vice versa), or preview defaults that don't match what
//   ships. Nothing in the type system catches that drift because the two
//   files intentionally have no import relationship (the admin console must
//   not depend on Cloud Functions runtime code).
//
//   This script is a zero-dependency, Node-builtins-only text-level check
//   that extracts the shared blocks from both files, normalizes away
//   comment/formatting differences, and diffs what's left. It runs from
//   Governance CI via tests/governance/config_contract_drift_test.sh.
//
// What to do when it fails:
//   Update BOTH files so the reported block matches again. Do not "fix" the
//   check by only touching one side, and do not silence a real mismatch by
//   loosening the normalizer. If a mismatch is intentional (a real contract
//   change), the change belongs in functions/src/config/configLoader.ts
//   first (it is the source of truth), then must be mirrored into
//   website/src/lib/admin/config-validation.ts in the same change.
//
// Usage: node tests/cross-system/config-contract-drift.mjs
// Exit 0 = the two files agree on every compared block. Exit 1 = drift (or a
// block/export is missing on one side).

import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..", "..");

const FUNCTIONS_FILE = path.join(repoRoot, "functions/src/config/configLoader.ts");
const WEBSITE_FILE = path.join(repoRoot, "website/src/lib/admin/config-validation.ts");
const FUNCTIONS_LABEL = "functions/src/config/configLoader.ts";
const WEBSITE_LABEL = "website/src/lib/admin/config-validation.ts";

// The fixed set of exports both files are documented to keep in sync.
const FIXED_BLOCKS = [
  { name: "DEFAULT_PROGRESSION_CONFIG", kind: "const" },
  { name: "DEFAULT_LEADERBOARD_CONFIG", kind: "const" },
  { name: "DEFAULT_FEATURE_ACCESS_CONFIG", kind: "const" },
  { name: "deepMerge", kind: "function" },
  { name: "validateProgressionConfig", kind: "function" },
  { name: "validateLeaderboardConfig", kind: "function" },
  { name: "validateFeatureAccessConfig", kind: "function" },
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
 * Extracts the source text of `export const NAME = { ... };` or
 * `export function NAME(...) { ... }` from `text`, by locating the
 * declaration and brace/paren-matching to its end. Returns null if the
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
    const braceIndex = text.indexOf("{", eqIndex);
    const braceEnd = findMatchingIndex(text, braceIndex, "{", "}");
    let end = braceEnd + 1;
    let cursor = end;
    while (cursor < text.length && /\s/.test(text[cursor])) {
      cursor += 1;
    }
    if (text[cursor] === ";") {
      end = cursor + 1;
    }
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
 * identifiers, operators, string/template literals). Steps:
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

  // Strip // line comments. None of the target blocks contain string
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

function discoverExportNames(text) {
  const names = new Set();
  const defaultConfigRe = /export const (DEFAULT_[A-Z0-9_]*_CONFIG)\b/g;
  const validateConfigRe = /export function (validate[A-Za-z0-9_]*Config)\b/g;

  for (const re of [defaultConfigRe, validateConfigRe]) {
    let match;
    while ((match = re.exec(text)) !== null) {
      names.add(match[1]);
    }
  }
  return names;
}

function kindForDiscoveredName(name) {
  return name.startsWith("DEFAULT_") ? "const" : "function";
}

function main() {
  // The admin console lives in a SEPARATE git repository that merely happens to
  // sit at website/ in a local checkout. Hosted CI clones only this repository,
  // so the mirror is genuinely absent there and reading it would crash. Report
  // the skip loudly rather than pretending the contract was verified: this
  // check is a local/dev guard, and the mirror's own repository is responsible
  // for its side.
  if (!existsSync(WEBSITE_FILE)) {
    console.log(
      `SKIP: config contract not compared — ${WEBSITE_LABEL} is not present. ` +
        "The admin console is a separate repository; this check only runs where both are checked out.",
    );
    return 0;
  }

  const functionsText = readText(FUNCTIONS_FILE);
  const websiteText = readText(WEBSITE_FILE);

  const mismatches = [];

  // 1. Catch a config export that exists on only one side (e.g. a new
  //    DEFAULT_*_CONFIG / validate*Config added to one file but not mirrored).
  const discoveredFunctions = discoverExportNames(functionsText);
  const discoveredWebsite = discoverExportNames(websiteText);

  for (const name of discoveredFunctions) {
    if (!discoveredWebsite.has(name)) {
      mismatches.push(
        `export '${name}' found in ${FUNCTIONS_LABEL} but missing from ${WEBSITE_LABEL}.`,
      );
    }
  }
  for (const name of discoveredWebsite) {
    if (!discoveredFunctions.has(name)) {
      mismatches.push(
        `export '${name}' found in ${WEBSITE_LABEL} but missing from ${FUNCTIONS_LABEL}.`,
      );
    }
  }

  // 2. Build the full comparison set: the fixed contract blocks, plus any
  //    regex-discovered DEFAULT_*_CONFIG / validate*Config export present in
  //    both files (so a new config document added symmetrically is still
  //    compared, not silently skipped).
  const fixedNames = new Set(FIXED_BLOCKS.map((block) => block.name));
  const blocksToCompare = [...FIXED_BLOCKS];

  for (const name of discoveredFunctions) {
    if (fixedNames.has(name)) {
      continue;
    }
    if (discoveredWebsite.has(name)) {
      blocksToCompare.push({ name, kind: kindForDiscoveredName(name) });
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
    console.error("FAIL: config contract drift detected between:");
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

  console.log(`PASS: config contract in sync (compared: ${compared.join(", ")})`);
  process.exit(0);
}

main();
