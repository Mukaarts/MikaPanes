#!/usr/bin/env bash
#
# test.sh — run the unit tests.
#
# Swift Testing ships inside the Command Line Tools but isn't on the default
# search/run paths, so we point the compiler, linker and dyld at it explicitly.
# (With full Xcode installed, plain `swift test` works without this wrapper.)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/.."

DEV="$(xcode-select -p)"
FW="${DEV}/Library/Developer/Frameworks"
INTEROP="${DEV}/Library/Developer/usr/lib"

if [[ ! -d "${FW}/Testing.framework" ]]; then
  echo "note: Testing.framework not found under ${FW}; falling back to plain swift test" >&2
  exec swift test "$@"
fi

exec swift test \
  -Xswiftc -F -Xswiftc "${FW}" \
  -Xlinker -F -Xlinker "${FW}" \
  -Xlinker -rpath -Xlinker "${FW}" \
  -Xlinker -rpath -Xlinker "${INTEROP}" \
  "$@"
