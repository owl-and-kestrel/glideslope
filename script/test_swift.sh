#!/usr/bin/env bash
set -euo pipefail

DEVELOPER_DIR="$(xcode-select -p)"
FRAMEWORKS_DIR="$DEVELOPER_DIR/Library/Developer/Frameworks"
DEVELOPER_LIB_DIR="$DEVELOPER_DIR/Library/Developer/usr/lib"

if [[ -d "$FRAMEWORKS_DIR/Testing.framework" ]]; then
  exec swift test "$@" \
    -Xswiftc -F \
    -Xswiftc "$FRAMEWORKS_DIR" \
    -Xlinker -F \
    -Xlinker "$FRAMEWORKS_DIR" \
    -Xlinker -rpath \
    -Xlinker "$FRAMEWORKS_DIR" \
    -Xlinker -rpath \
    -Xlinker "$DEVELOPER_LIB_DIR"
fi

# Full Xcode toolchains normally expose Swift Testing without additional search
# paths. Keep that standard path portable for contributors who are not using
# the standalone Command Line Tools package.
exec swift test "$@"
