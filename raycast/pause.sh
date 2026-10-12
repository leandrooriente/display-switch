#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Pause Monitor Follow
# @raycast.mode compact
# @raycast.packageName Monitor Follow
# @raycast.icon ⏸️
# @raycast.description Stop automatic switching until you run Enable again, including across logins.
set -euo pipefail
source "$(dirname "$0")/common.sh"
exec "$BASE/display-switch" pause
