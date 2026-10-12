#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Enable Monitor Follow
# @raycast.mode compact
# @raycast.packageName Monitor Follow
# @raycast.icon 🖥️
# @raycast.description Follow configured USB device arrivals and start automatically at login.
set -euo pipefail
source "$(dirname "$0")/common.sh"
exec "$BASE/display-switch" enable "$CONFIG"
