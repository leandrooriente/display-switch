#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Test USB Device Events
# @raycast.mode compact
# @raycast.packageName Monitor Follow
# @raycast.icon 🧪
# @raycast.description Replace live switching with log-only testing. Run Enable afterward to restore switching.
set -euo pipefail
source "$(dirname "$0")/common.sh"
exec "$BASE/display-switch" test "$CONFIG"
