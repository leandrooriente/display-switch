#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="$HOME/Library/Application Support/Display Switch"
if [[ $# -gt 1 ]]; then
  printf 'Usage: ./install.sh [mini|macbook|config.local.json]\n' >&2
  exit 1
fi

case "${1:-}" in
  mini|macbook) CONFIG="$ROOT/config.$1.example.json" ;;
  "")
    printf 'Install on which Mac?\n  1) Mac mini — HDMI 2\n  2) MacBook Pro — DisplayPort\nChoice: '
    read -r CHOICE
    case "$CHOICE" in
      1) CONFIG="$ROOT/config.mini.example.json" ;;
      2) CONFIG="$ROOT/config.macbook.example.json" ;;
      *) printf 'Choose 1 or 2. Nothing installed.\n' >&2; exit 1 ;;
    esac ;;
  *) CONFIG="$1" ;;
esac

if [[ ! -f "$CONFIG" || ! -r "$CONFIG" ]]; then
  printf 'Configuration file not found or unreadable: %s\n' "$CONFIG" >&2
  exit 1
fi

if [[ ! -x "$ROOT/bin/display-switch" ]]; then
  printf 'The helper is missing. Run ./build.sh, then try again.\n' >&2
  exit 1
fi

printf 'Checking BetterDisplay and installing the arrival-only helper…\n'
"$ROOT/bin/display-switch" validate "$CONFIG"
"$ROOT/bin/display-switch" enable "$CONFIG"
mkdir -p "$DEST/raycast"
cp "$ROOT"/raycast/*.sh "$DEST/raycast/"
chmod +x "$DEST"/raycast/*.sh
printf '\nInstalled. The helper starts automatically when you log in.\n'
printf 'Switch the USB connection away and back to test. Device disconnection is ignored.\n'
printf '\nOptional Raycast controls:\n'
printf 'Raycast Settings → Extensions → + → Add Script Directory\n%s\n' "$DEST/raycast"
printf '\nTo pause without Raycast:\n"%s/display-switch" pause\n' "$DEST"
