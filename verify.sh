#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
for SCRIPT in install.sh Install.command build.sh verify.sh raycast/*.sh; do
  /bin/bash -n "$SCRIPT"
done
/usr/bin/codesign --verify --strict bin/display-switch
ARCHS="$(/usr/bin/lipo -archs bin/display-switch)"
for ARCH in arm64 x86_64; do
  case " $ARCHS " in
    *" $ARCH "*) ;;
    *) printf 'FAIL: missing %s binary architecture.\n' "$ARCH" >&2; exit 1 ;;
  esac
done
/usr/bin/shasum -a 256 -c SHA256SUMS
if bin/display-switch watch missing-config.json --dry-run --once >/dev/null 2>&1; then
  printf 'FAIL: missing configuration was accepted.\n' >&2
  exit 1
fi
if bin/display-switch watch config.mini.example.json --unknown >/dev/null 2>&1; then
  printf 'FAIL: unknown watcher option was accepted.\n' >&2
  exit 1
fi
for CONFIG in config.mini.example.json config.macbook.example.json; do
  bin/display-switch validate "$CONFIG"
done

# Exercise the safety boundary before any configuration can be installed.
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT
reject_configuration() {
  printf '%s\n' "$1" > "$TEST_DIR/invalid.json"
  if bin/display-switch validate "$TEST_DIR/invalid.json" >/dev/null 2>&1; then
    printf 'FAIL: invalid configuration was accepted: %s\n' "$1" >&2
    exit 1
  fi
}
reject_configuration '{}'
reject_configuration '{"usbVendorID":0,"usbProductID":1,"monitorNameContains":"Display","inputCode":15}'
reject_configuration '{"usbVendorID":65536,"usbProductID":1,"monitorNameContains":"Display","inputCode":15}'
reject_configuration '{"usbVendorID":1,"usbProductID":-1,"monitorNameContains":"Display","inputCode":15}'
reject_configuration '{"usbVendorID":1,"usbProductID":65536,"monitorNameContains":"Display","inputCode":15}'
reject_configuration '{"usbVendorID":1,"usbProductID":1,"monitorNameContains":"  ","inputCode":15}'
reject_configuration '{"usbVendorID":1,"usbProductID":1,"monitorNameContains":"Display","inputCode":0}'
reject_configuration '{"usbVendorID":1,"usbProductID":1,"monitorNameContains":"Display","inputCode":256}'
reject_configuration '{"usbVendorID":1,"usbProductID":1,"monitorNameContains":"Display","inputCode":15,"inputName":""}'
reject_configuration '{"usbVendorID":1,"usbProductID":1,"monitorNameContains":"Display","inputCode":15,"settleDelaySeconds":-1}'
reject_configuration '{"usbVendorID":1,"usbProductID":1,"monitorNameContains":"Display","inputCode":15,"wakeSuppressionSeconds":121}'
reject_configuration '{"usbVendorID":1,"usbProductID":1,"monitorNameContains":"Display","inputCode":15,"settleDelaySecond":1}'
printf '%s\n' '{"usbVendorID":65535,"usbProductID":0,"monitorNameContains":"Other monitor","inputCode":255}' > "$TEST_DIR/minimal.json"
bin/display-switch validate "$TEST_DIR/minimal.json"

for CONFIG in config.mini.example.json config.macbook.example.json "$TEST_DIR/minimal.json"; do
  OUTPUT="$(bin/display-switch watch "$CONFIG" --dry-run --once)"
  printf '%s\n' "$OUTPUT"
  case "$OUTPUT" in
    *"TEST watcher ready for "*"initial state ignored."*) ;;
    *) printf 'FAIL: event-only watcher did not initialize.\n' >&2; exit 1 ;;
  esac
done
printf 'Checks passed. No monitor changes or installation were performed.\n'
