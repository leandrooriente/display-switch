#!/bin/bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$ROOT/install.sh"
RESULT=$?
printf '\nPress Return to close. '
read -r REPLY
exit "$RESULT"
