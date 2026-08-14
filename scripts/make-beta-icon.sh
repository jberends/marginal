#!/usr/bin/env bash
#
# Builds the AppIconBeta.appiconset (the development/beta app icon) by resizing the
# designed 1024px source at assets/icon/marginal-icon-3-beta_1024.png into every
# macOS icon slot. The production icon (AppIcon) is a separate, unchanged set.
#
# To switch the app between beta and production icons, change
# ASSETCATALOG_COMPILER_APPICON_NAME in project.yml (see the release checklist in
# AGENTS.md). This script only (re)generates the beta set's PNGs from the source art.
#
# Run:  scripts/make-beta-icon.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

SRC="assets/icon/marginal-icon-3-beta_1024.png"
DST="Sources/Marginal/App/Assets.xcassets/AppIconBeta.appiconset"

if [[ ! -f "${SRC}" ]]; then
  echo "error: source icon not found at ${SRC}" >&2
  exit 1
fi

rm -rf "${DST}"
mkdir -p "${DST}"

# slot: "<point-size> <scale> <pixels>"
slots=(
  "16x16 1x 16"
  "16x16 2x 32"
  "32x32 1x 32"
  "32x32 2x 64"
  "128x128 1x 128"
  "128x128 2x 256"
  "256x256 1x 256"
  "256x256 2x 512"
  "512x512 1x 512"
  "512x512 2x 1024"
)

entries=()
for slot in "${slots[@]}"; do
  read -r size scale px <<< "${slot}"
  name="beta-${size}-${scale}.png"
  sips -s format png -z "${px}" "${px}" "${SRC}" --out "${DST}/${name}" >/dev/null
  entries+=("    {
      \"filename\" : \"${name}\",
      \"idiom\" : \"mac\",
      \"scale\" : \"${scale}\",
      \"size\" : \"${size}\"
    }")
  echo "wrote ${name} (${px}px)"
done

# Join entries with commas into Contents.json.
{
  echo '{'
  echo '  "images" : ['
  for i in "${!entries[@]}"; do
    printf '%s' "${entries[$i]}"
    if [[ $i -lt $(( ${#entries[@]} - 1 )) ]]; then echo ','; else echo ''; fi
  done
  echo '  ],'
  echo '  "info" : {'
  echo '    "author" : "marginal-make-beta-icon",'
  echo '    "version" : 1'
  echo '  }'
  echo '}'
} > "${DST}/Contents.json"

echo "Done -> ${DST}"
