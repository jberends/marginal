#!/usr/bin/env bash
#
# Build a side-by-side, locally-installable copy of Marginal that coexists with the
# App Store / released build. It gets a version-suffixed bundle identifier
# (com.jochemberends.marginal.v0100) and is ad-hoc signed, so macOS treats it as a
# distinct app and you can choose which one to launch.
#
# NOT for distribution — ad-hoc signed, sandboxed, local only.
#
# Usage:  scripts/build-sidebyside.sh
# Output: /Applications/Marginal-<MARKETING_VERSION>.app
#
set -euo pipefail
cd "$(dirname "$0")/.."

# Read the marketing version straight from project.yml (single source of truth).
VERSION="$(grep -E '^\s*MARKETING_VERSION:' project.yml | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
if [[ -z "${VERSION}" ]]; then
  echo "error: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

# Version-suffixed bundle id: 0.10.0 -> v0100 (strip dots).
SUFFIX="v$(echo "${VERSION}" | tr -d '.')"
BUNDLE_ID="com.jochemberends.marginal.${SUFFIX}"
APP_NAME="Marginal-${VERSION}"
DERIVED="build/sidebyside-${SUFFIX}"
DEST="/Applications/${APP_NAME}.app"

echo "==> Regenerating the β-badged beta app icon"
swift scripts/make-beta-icon.swift

echo "==> Regenerating Xcode project (xcodegen)"
xcodegen generate

echo "==> Building Release (${BUNDLE_ID}, β icon)"
# Never run two xcodebuild processes at once — they corrupt the shared module cache.
# ASSETCATALOG_COMPILER_APPICON_NAME selects the beta icon set for THIS build only;
# the released build (project.yml) still uses AppIcon.
xcodebuild \
  -project Marginal.xcodeproj \
  -scheme Marginal \
  -configuration Release \
  -derivedDataPath "${DERIVED}" \
  PRODUCT_BUNDLE_IDENTIFIER="${BUNDLE_ID}" \
  ASSETCATALOG_COMPILER_APPICON_NAME=AppIconBeta \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="" \
  ENABLE_HARDENED_RUNTIME=NO \
  build

BUILT="${DERIVED}/Build/Products/Release/Marginal.app"
if [[ ! -d "${BUILT}" ]]; then
  echo "error: build product not found at ${BUILT}" >&2
  exit 1
fi

echo "==> Installing to ${DEST}"
rm -rf "${DEST}"
cp -R "${BUILT}" "${DEST}"

# Re-sign ad-hoc after the copy so the on-disk bundle is internally consistent.
codesign --force --deep --sign - \
  --entitlements Sources/Marginal/App/Marginal.entitlements \
  "${DEST}"

echo "==> Done."
echo "    App:       ${DEST}"
echo "    Bundle id: ${BUNDLE_ID}"
echo "    Version:   ${VERSION}"
echo "    Launch:    open \"${DEST}\""
