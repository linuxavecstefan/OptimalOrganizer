#!/bin/sh
set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$PROJECT_DIR"

flutter --no-version-check build linux --release

BUNDLE="$PROJECT_DIR/build/linux/x64/release/bundle"
SQLITE_LIBRARY=$(ldconfig -p | awk '$1 == "libsqlite3.so.0" { print $NF; exit }')
if [ -z "$SQLITE_LIBRARY" ] || [ ! -r "$SQLITE_LIBRARY" ]; then
    echo "Could not find the Linux SQLite runtime library (libsqlite3.so.0)." >&2
    exit 1
fi

install -m 755 "$SQLITE_LIBRARY" "$BUNDLE/lib/libsqlite3.so"
echo "Bundled SQLite runtime at $BUNDLE/lib/libsqlite3.so"
