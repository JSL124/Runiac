#!/usr/bin/env node
// paywall-config-drift.mjs
//
// What this protects:
//   The `config/paywall` document schema is shared by two hand-maintained
//   mirrors with intentionally no import relationship:
//     - mobile/lib/features/paywall/domain/models/
//       paywall_config_read_model.dart (read-only consumer in the app), and
//     - website/src/lib/admin/paywall-config.ts (the admin console's editor
//       defaults + validation, the only writer).
//   The canonical default document lives in
//   tests/cross-system/fixtures/paywall-config-defaults.json. This script
//   verifies the website side's DEFAULT_PAYWALL_CONFIG equals the fixture;
//   the Flutter side is verified against the same fixture by
//   mobile/test/paywall_config_defaults_fixture_test.dart.
//   If a side drifts, the paywall an admin previews and the paywall the app
//   renders on a missing/partial document stop matching.
//
// What to do when it fails:
//   A schema/default change must update all three files together: the
//   fixture, the Dart model defaults, and the website module.
//
// Usage: node tests/cross-system/paywall-config-drift.mjs
// Exit 0 = website defaults match the fixture (or website/ is absent, which
// is reported as a loud skip). Exit 1 = drift or extraction failure.

import { existsSync, readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "..", "..");

const FIXTURE_FILE = path.join(
  scriptDir,
  "fixtures/paywall-config-defaults.json",
);
const WEBSITE_FILE = path.join(repoRoot, "website/src/lib/admin/paywall-config.ts");
const WEBSITE_LABEL = "website/src/lib/admin/paywall-config.ts";

// Extracts the DEFAULT_PAYWALL_CONFIG object literal by brace matching and
// converts it to JSON (quote identifier keys, drop trailing commas). The
// literal is data-only by contract — strings, booleans, numbers, arrays,
// objects — so this textual conversion is exact.
function extractWebsiteDefaults(sourceText) {
  const marker = "export const DEFAULT_PAYWALL_CONFIG";
  const markerIndex = sourceText.indexOf(marker);
  if (markerIndex === -1) {
    throw new Error(`DEFAULT_PAYWALL_CONFIG not found in ${WEBSITE_LABEL}`);
  }
  const braceStart = sourceText.indexOf("{", markerIndex);
  if (braceStart === -1) {
    throw new Error("DEFAULT_PAYWALL_CONFIG has no object literal");
  }
  let depth = 0;
  let inString = null;
  let end = -1;
  for (let i = braceStart; i < sourceText.length; i += 1) {
    const char = sourceText[i];
    if (inString !== null) {
      if (char === "\\") {
        i += 1;
      } else if (char === inString) {
        inString = null;
      }
      continue;
    }
    if (char === '"' || char === "'") {
      inString = char;
    } else if (char === "{") {
      depth += 1;
    } else if (char === "}") {
      depth -= 1;
      if (depth === 0) {
        end = i;
        break;
      }
    }
  }
  if (end === -1) {
    throw new Error("DEFAULT_PAYWALL_CONFIG object literal is unbalanced");
  }
  const literal = sourceText.slice(braceStart, end + 1);
  const asJson = literal
    // Quote bare identifier keys: `title:` -> `"title":`
    .replace(/([{,]\s*)([A-Za-z_][A-Za-z0-9_]*)\s*:/g, '$1"$2":')
    // Drop trailing commas before a closing bracket/brace.
    .replace(/,\s*([}\]])/g, "$1");
  return JSON.parse(asJson);
}

function deepEqual(a, b, trail = "$") {
  if (Object.is(a, b)) {
    return [];
  }
  if (
    typeof a !== "object" || a === null ||
    typeof b !== "object" || b === null
  ) {
    return [`${trail}: fixture ${JSON.stringify(a)} !== website ${JSON.stringify(b)}`];
  }
  const aKeys = Object.keys(a).sort();
  const bKeys = Object.keys(b).sort();
  const diffs = [];
  for (const key of new Set([...aKeys, ...bKeys])) {
    if (!(key in a)) {
      diffs.push(`${trail}.${key}: missing from the fixture`);
    } else if (!(key in b)) {
      diffs.push(`${trail}.${key}: missing from ${WEBSITE_LABEL}`);
    } else {
      diffs.push(...deepEqual(a[key], b[key], `${trail}.${key}`));
    }
  }
  return diffs;
}

// The website repo is a sibling checkout that sits at website/ in a local
// clone; hosted CI may clone only this repository. Report the skip loudly
// rather than pretending the contract was verified.
if (!existsSync(WEBSITE_FILE)) {
  console.log(
    `SKIP paywall-config-drift: ${WEBSITE_LABEL} not present in this checkout.`,
  );
  process.exit(0);
}

const fixture = JSON.parse(readFileSync(FIXTURE_FILE, "utf8"));
const websiteDefaults = extractWebsiteDefaults(readFileSync(WEBSITE_FILE, "utf8"));
const diffs = deepEqual(fixture, websiteDefaults);

if (diffs.length > 0) {
  console.error("paywall-config-drift: DEFAULT_PAYWALL_CONFIG drifted from the fixture:");
  for (const diff of diffs) {
    console.error(`  ${diff}`);
  }
  process.exit(1);
}

console.log("paywall-config-drift: website defaults match the fixture.");
