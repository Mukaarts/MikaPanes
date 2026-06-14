#!/usr/bin/env bash
#
# make-icon.sh — render the app icon and build Resources/AppIcon.icns.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "${ICONSET}"

echo "==> Rendering icon PNGs…"
swift "${SCRIPT_DIR}/make-icon.swift" "${ICONSET}"

echo "==> Building AppIcon.icns…"
iconutil -c icns "${ICONSET}" -o "${ROOT_DIR}/Resources/AppIcon.icns"

echo "==> Done: Resources/AppIcon.icns"
