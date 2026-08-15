#!/usr/bin/env bash
#
# Runiac — one-shot local setup.
#
# Installs every dependency and creates every configuration file the three
# components need, leaving exactly one thing for you to do: paste in your own
# keys. Run it from anywhere:
#
#   ./scripts/setup.sh
#
# Safe to re-run. An existing configuration file is never overwritten, so your
# filled-in keys survive a second run.
#
# What you get with NO keys filled in: the Flutter app builds and runs in
# offline mode against local demo data, the website builds, and the Cloud
# Functions compile and their test suite passes. Keys are only needed to reach
# a real Firebase backend — see the checklist this script prints at the end.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

created=()
kept=()

# Copy template -> destination, but never clobber a file that already exists.
install_template() {
  local template="$1" destination="$2"
  if [ ! -f "$template" ]; then
    echo "  !  missing template: $template" >&2
    return 1
  fi
  if [ -e "$destination" ]; then
    kept+=("$destination")
    return 0
  fi
  mkdir -p "$(dirname "$destination")"
  cp "$template" "$destination"
  created+=("$destination")
}

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }

step "Checking prerequisites"
missing_tools=()
for tool in flutter node npm; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  ok   %-8s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '  MISSING %s\n' "$tool"
    missing_tools+=("$tool")
  fi
done
# Java is needed only to build the Android app and to run the Firebase
# emulator; the offline web/functions path does not touch it.
if command -v java >/dev/null 2>&1; then
  printf '  ok   %-8s %s\n' "java" "$(command -v java)"
else
  printf '  note java not found — needed for Android builds and the Firebase emulator\n'
fi
if [ ${#missing_tools[@]} -gt 0 ]; then
  echo
  echo "Install these first, then re-run: ${missing_tools[*]}" >&2
  echo "See README section 3 for the versions this project was built against." >&2
  exit 1
fi

step "Creating configuration files from templates"
install_template ".firebaserc.example"                            ".firebaserc"
install_template "mobile/dart_define.example.json"                "mobile/dart_define.local.json"
install_template "website/.env.local.example"                     "website/.env.local"

# `${arr[@]+...}` guards the empty-array case: under `set -u`, bash 3.2 (the
# version macOS ships) treats an unset element expansion as an unbound variable.
for f in ${created[@]+"${created[@]}"}; do printf '  created  %s\n' "$f"; done
for f in ${kept[@]+"${kept[@]}"};       do printf '  kept     %s (already existed)\n' "$f"; done

# google-services.json is deliberately NOT generated. Every value in it is
# issued by the Firebase console and none can be synthesised here, and its mere
# presence switches the Android build onto the google-services plugin. Absent,
# the app builds and runs offline — which is the better default for a first run.
printf '  skipped  mobile/android/app/google-services.json (download it from Firebase; see the checklist below)\n'

step "Installing Cloud Functions dependencies"
(cd functions && npm ci --no-audit --no-fund)

step "Installing website dependencies"
(cd website && npm ci --no-audit --no-fund)

step "Fetching Flutter packages"
(cd mobile && flutter pub get)

step "Setup complete"
cat <<'SUMMARY'

Everything is wired up. You can run the app right now, with no keys at all:

    cd mobile && flutter run --dart-define-from-file=dart_define.local.json

That starts Runiac in OFFLINE mode. The app builds, launches and renders on
local demo data. Note that SIGN-IN IS REFUSED in this mode by design — there
is no backend to hold an account, so it says so instead of pretending.

To get past sign-in with still no keys, run the local Firebase emulator
instead (needs Java 17 + the Firebase CLI, no credentials):

    firebase emulators:start
    cd mobile && flutter run \
      --dart-define=RUNIAC_FIREBASE_EMULATOR=true \
      --dart-define=RUNIAC_FIREBASE_EMULATOR_HOST=127.0.0.1

Nothing below is required for either of those.

--------------------------------------------------------------------------
To connect a real Firebase backend, fill in these keys — nothing else.
--------------------------------------------------------------------------

1. mobile/dart_define.local.json
     RUNIAC_FIREBASE_API_KEY                Firebase console > Project
     RUNIAC_FIREBASE_APP_ID                 settings > General > Your apps
     RUNIAC_FIREBASE_MESSAGING_SENDER_ID
     RUNIAC_FIREBASE_PROJECT_ID
     RUNIAC_FIREBASE_STORAGE_BUCKET
     MAPBOX_PUBLIC_ACCESS_TOKEN             account.mapbox.com (optional —
                                            without it maps show a placeholder)
   THEN flip RUNIAC_FIREBASE_PRODUCTION to "true".
   Leaving it "false" keeps the app offline no matter what else you fill in;
   setting it "true" with any of the first four still blank fails on launch
   by design.

2. .firebaserc
     projects.default                       your Firebase project id

3. mobile/android/app/google-services.json
   Not fillable by hand — download it from the Firebase console
   (Project settings > Your apps > Android) and drop it in that folder.
   Register the Android app under package name exactly:

     com.runiac.runiac_app

   mobile/android/app/google-services.example.json shows the shape you
   should end up with.

4. website/.env.local
   Ships pointing at the local Firebase emulator, which needs no keys.
   For a live backend, comment out the two *_EMULATOR_HOST lines and set
   FIREBASE_SERVICE_ACCOUNT_KEY and NEXT_PUBLIC_FIREBASE_API_KEY instead.
   The file documents both modes inline.

5. Coaching features (optional)
     firebase functions:secrets:set OPENAI_API_KEY

None of these files are tracked by git, so your keys stay local.

SUMMARY
