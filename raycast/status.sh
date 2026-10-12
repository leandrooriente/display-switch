#!/bin/bash
# @raycast.schemaVersion 1
# @raycast.title Monitor Follow Status
# @raycast.mode fullOutput
# @raycast.packageName Monitor Follow
# @raycast.icon ℹ️
# @raycast.description Show the selected input, whether the helper is loaded, and recent events.
set -euo pipefail
source "$(dirname "$0")/common.sh"
exec "$BASE/display-switch" status
