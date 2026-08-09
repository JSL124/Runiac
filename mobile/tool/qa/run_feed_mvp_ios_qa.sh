#!/usr/bin/env bash
set -euo pipefail

# Kept as a thin wrapper so existing muscle memory and any external references
# keep working. New QA runs should call run_qa_surface.sh directly, which
# supports every surface and both platforms.
#
# The simulator UDID that used to be hardcoded here is gone: a stale UDID fails
# with a confusing flutter error. Pass -d, or set RUNIAC_QA_DEVICE.

exec "$(dirname "$0")/run_qa_surface.sh" feed_mvp --ios "$@"
