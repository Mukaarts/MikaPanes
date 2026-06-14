#!/usr/bin/env bash
#
# bundle.sh — build MikaPanes and wrap the SwiftPM binary into a signed .app bundle.
#
# Usage:
#   ./Scripts/bundle.sh            # build -> ./build/MikaPanes.app
#   ./Scripts/bundle.sh --install  # also copy -> /Applications/MikaPanes.app
#
set -euo pipefail

APP_NAME="MikaPanes"
BUNDLE_ID="com.mikapanes.app"
CONFIG="release"

# Resolve repo root (parent of this script's directory).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${ROOT_DIR}"

INSTALL=0
if [[ "${1:-}" == "--install" ]]; then
  INSTALL=1
fi

echo "==> Building ${APP_NAME} (${CONFIG})…"
swift build -c "${CONFIG}"

BIN_PATH="$(swift build -c "${CONFIG}" --show-bin-path)/${APP_NAME}"
if [[ ! -f "${BIN_PATH}" ]]; then
  echo "error: built binary not found at ${BIN_PATH}" >&2
  exit 1
fi

APP_DIR="${ROOT_DIR}/build/${APP_NAME}.app"
echo "==> Assembling ${APP_DIR}…"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BIN_PATH}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
cp "${ROOT_DIR}/Resources/Info.plist" "${APP_DIR}/Contents/Info.plist"

# App icon: generate on first run if missing, then copy into the bundle.
if [[ ! -f "${ROOT_DIR}/Resources/AppIcon.icns" ]]; then
  echo "==> AppIcon.icns missing; generating…"
  "${SCRIPT_DIR}/make-icon.sh"
fi
cp "${ROOT_DIR}/Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"

ENTITLEMENTS="${ROOT_DIR}/Resources/${APP_NAME}.entitlements"

sign_app() {
  local target="$1"
  echo "==> Ad-hoc signing ${target}…"
  codesign --force --sign - \
    --entitlements "${ENTITLEMENTS}" \
    --identifier "${BUNDLE_ID}" \
    "${target}"
}

sign_app "${APP_DIR}"

if [[ "${INSTALL}" -eq 1 ]]; then
  DEST="/Applications/${APP_NAME}.app"
  echo "==> Installing to ${DEST}…"
  rm -rf "${DEST}"
  cp -R "${APP_DIR}" "${DEST}"
  sign_app "${DEST}"
  echo "==> Installed. Launch with: open -a ${APP_NAME}"
else
  echo "==> Done. Launch with: open \"${APP_DIR}\""
fi
