#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$ROOT/.build"
mkdir -p "$BUILD/module-cache" "$ROOT/bin"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -warnings-as-errors -O \
    -target "$ARCH-apple-macosx13.0" -module-cache-path "$BUILD/module-cache" \
    "$ROOT/source/main.swift" -o "$BUILD/display-switch-$ARCH"
done
xcrun lipo -create "$BUILD/display-switch-arm64" "$BUILD/display-switch-x86_64" \
  -output "$ROOT/bin/display-switch"
/usr/bin/codesign --force --sign - "$ROOT/bin/display-switch"
/usr/bin/codesign --verify --strict "$ROOT/bin/display-switch"
(cd "$ROOT" && /usr/bin/shasum -a 256 bin/display-switch > SHA256SUMS)
printf 'Built universal helper for Apple silicon and Intel Macs (macOS 13+).\n'
