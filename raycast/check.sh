#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Check BetterDisplay Connection
# @raycast.mode fullOutput
# @raycast.packageName Monitor Follow
# @raycast.icon 🔎
# @raycast.description Check the configured monitor without changing its input or printing identifiers.
set -euo pipefail
source "$(dirname "$0")/common.sh"
exec "$BASE/display-switch" check "$CONFIG"
