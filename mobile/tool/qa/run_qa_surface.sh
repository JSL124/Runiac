#!/usr/bin/env bash
set -euo pipefail

# Launch one of the app's QA surfaces on a chosen device.
#
# Usage:
#   tool/qa/run_qa_surface.sh <surface> [-d <device-id>] [--ios|--android]
#   RUNIAC_QA_DEVICE=<device-id> tool/qa/run_qa_surface.sh <surface>
#
# Examples:
#   tool/qa/run_qa_surface.sh app_tour -d "iPhone 17"
#   tool/qa/run_qa_surface.sh premium_paywall --android
#   tool/qa/run_qa_surface.sh --list
#
# Replaces the hardcoded-simulator script that only ever launched one surface.
# Device is now required rather than defaulted, because a stale UDID fails with
# a confusing flutter error rather than an obvious one.

cd "$(dirname "$0")/../.."

# Surface tokens are the `*QaSurfaceName` constants the launchers compare
# `RUNIAC_QA_SURFACE` against. Keep in sync with lib/features/**/qa/.
SURFACES=(app_tour feed_mvp leaderboard_ranking plan_completion premium_paywall xp_update)

usage() {
  cat <<'USAGE'
Usage: tool/qa/run_qa_surface.sh <surface> [-d <device-id>] [--ios|--android]

Surfaces:
  app_tour             First-run character-led tour (arms on signup only)
  feed_mvp             Feed list and post interactions
  leaderboard_ranking  Monthly leaderboard and rank presentation
  plan_completion      Plan-completion ceremony
  premium_paywall      Paywall presentation and tier gating
  xp_update            XP award presentation after a run

Options:
  -d <device-id>   Target device. Also read from $RUNIAC_QA_DEVICE.
  --ios            Apply the iOS pre-run steps (SPM manifest + pod install).
  --android        Skip the iOS pre-run steps.
  --list           Print available devices and exit.

If neither --ios nor --android is given, the iOS steps run only when the
device id looks like a simulator UDID or contains "iPhone"/"iPad".
USAGE
}

[[ $# -eq 0 ]] && { usage; exit 1; }

if [[ "${1:-}" == "--list" ]]; then
  flutter devices
  exit 0
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

surface="$1"
shift

matched=0
for s in "${SURFACES[@]}"; do
  [[ "$s" == "$surface" ]] && matched=1
done
if [[ "$matched" -ne 1 ]]; then
  echo "Unknown surface: $surface" >&2
  echo >&2
  usage >&2
  exit 1
fi

device="${RUNIAC_QA_DEVICE:-}"
platform=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d) device="${2:-}"; shift 2 ;;
    --ios) platform="ios"; shift ;;
    --android) platform="android"; shift ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ -z "$device" ]]; then
  echo "No device given. Pass -d <device-id> or set RUNIAC_QA_DEVICE." >&2
  echo >&2
  echo "Available devices:" >&2
  flutter devices >&2
  exit 1
fi

# Infer the platform when not stated, so the common case needs no flag.
if [[ -z "$platform" ]]; then
  if [[ "$device" =~ ^[0-9A-F]{8}-[0-9A-F]{4} || "$device" == *iPhone* || "$device" == *iPad* ]]; then
    platform="ios"
  else
    platform="android"
  fi
fi

echo "surface=$surface device=$device platform=$platform"

flutter pub get

if [[ "$platform" == "ios" ]]; then
  # `flutter pub get` (and `flutter analyze` / `flutter test`) regenerate the
  # SwiftPM manifest pinned at iOS 13.0, while Firebase requires 15.0. Left
  # alone this surfaces later as a confusing Xcode build failure, so patch it
  # immediately after pub get and before pod install.
  package_manifest="ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
  if [[ -f "$package_manifest" ]]; then
    perl -0pi -e 's/\.iOS\("13\.0"\)/.iOS("15.0")/g' "$package_manifest"
    echo "patched $package_manifest to iOS 15.0"
  fi
  (cd ios && pod install)
fi

flutter run -d "$device" --dart-define=RUNIAC_QA_SURFACE="$surface"
