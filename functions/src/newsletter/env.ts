// Base URLs are read from the environment (never hardcoded secrets — these
// are public URLs, not credentials) with the current production values as
// defaults, matching how other modules in this codebase read
// process.env[...] directly rather than through a config file.
export function siteBaseUrl(): string {
  return process.env["RUNIAC_SITE_BASE_URL"] ?? "https://fyp-website-v2.vercel.app";
}

export function functionsBaseUrl(): string {
  return process.env["RUNIAC_FUNCTIONS_BASE_URL"] ?? "https://asia-southeast1-runiac-fypp.cloudfunctions.net";
}
