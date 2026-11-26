#!/bin/zsh
#
# Builds the release disk images: one for Apple Silicon, one for Intel.
#
#   scripts/release.sh            build both DMGs into dist/
#   scripts/release.sh --beta N   build DMGs and ZIPs for beta build N
#   scripts/release.sh --publish  also create the GitHub release for this version
#
# The version comes from the Xcode project (MARKETING_VERSION). Release notes
# for --publish are read from dist/notes-<version>.md: the changelog only; the
# download and install instructions are appended here.
#

set -euo pipefail
TRAPZERR() { print -u2 -- "Release packaging failed at ${funcfiletrace[1]} (status $?)."; }

cd "$(dirname "$0")/.."
ROOT="$PWD"
DIST="$ROOT/dist"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

VERSION=$(xcodebuild -project Nearo.xcodeproj -target Nearo -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MARKETING_VERSION = / { print $2 }')
MIN_MACOS=$(xcodebuild -project Nearo.xcodeproj -target Nearo -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ MACOSX_DEPLOYMENT_TARGET = / { print $2 }')
[[ -n "$VERSION" ]] || { echo "Could not read MARKETING_VERSION" >&2; exit 1; }

dmg_prefix=Nearo
build_settings=()
if [[ ${1:-} == --beta ]]; then
  [[ $# == 2 && $2 == <1-> ]] || { echo "Usage: scripts/release.sh --beta BUILD_NUMBER" >&2; exit 2; }
  build_settings=("CURRENT_PROJECT_VERSION=$2")
  VERSION="$VERSION-beta.$2"
  dmg_prefix="Nearo-$VERSION"
fi

# Only local previews and beta packages may use an ad-hoc signature.
identity=${NEARO_SIGNING_IDENTITY:--}
if [[ ${1:-} == --publish || ${NEARO_REQUIRE_SIGNING:-0} == 1 ]]; then
  [[ "$identity" != - ]] || { print -u2 "A stable release needs NEARO_SIGNING_IDENTITY (see docs/signing.md)."; exit 1; }
fi
sign_args=(--force --deep --sign "$identity")
if [[ -n ${NEARO_SIGNING_KEYCHAIN:-} ]]; then
  sign_args+=(--keychain "$NEARO_SIGNING_KEYCHAIN")
fi

mkdir -p "$DIST"
echo "Nearo $VERSION (macOS $MIN_MACOS+)"

# A freshly created image can stay busy briefly on hosted macOS runners.
run_hdiutil() {
  local attempt
  for attempt in 1 2 3 4; do
    if hdiutil "$@"; then return 0; fi
    (( attempt < 4 )) || return 1
    sleep $((attempt * 5))
  done
}

# arch   label (used in the file name)
for pair in "arm64 AppleSilicon" "x86_64 Intel"; do
  arch=${pair%% *}
  label=${pair##* }
  derived="$BUILD/$arch"
  echo "\n==> Building $label ($arch)"

  xcodebuild -project Nearo.xcodeproj -scheme Nearo -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$derived" \
    ARCHS="$arch" ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    DEPLOYMENT_POSTPROCESSING=YES ENABLE_CODE_COVERAGE=NO CLANG_COVERAGE_MAPPING=NO \
    "${build_settings[@]}" build -quiet

  app="$derived/Build/Products/Release/Nearo.app"
  binary="$app/Contents/MacOS/Nearo"

  # Fix framework symlinks if present
  FRAMEWORK="$app/Contents/Frameworks/MediaRemoteAdapter.framework"
  if [[ -d "$FRAMEWORK" ]]; then
    cd "$FRAMEWORK"
    rm -rf MediaRemoteAdapter Resources Current Versions/Current
    ln -s A Versions/Current
    ln -s Versions/Current/MediaRemoteAdapter MediaRemoteAdapter
    ln -s Versions/Current/Resources Resources
    cd "$ROOT"
  fi

  codesign "${sign_args[@]}" "$app"
  codesign --verify --deep --strict "$app"

  # The updater downloads the zip; people download the disk image.
  zip="$DIST/Nearo-$VERSION-$label.zip"
  rm -f "$zip"
  ditto -c -k --keepParent "$app" "$zip"

  staging="$BUILD/dmg-$arch"
  mkdir -p "$staging"
  ditto "$app" "$staging/Nearo.app"
  ln -s /Applications "$staging/Applications"

  dmg="$DIST/$dmg_prefix-$label.dmg"
  rm -f "$dmg"
  echo "Creating $(basename "$dmg")"
  run_hdiutil create -ov -volname "Nearo $VERSION" -srcfolder "$staging" \
    -format UDZO -imagekey zlib-level=9 "$dmg"
  run_hdiutil verify "$dmg"
  echo "    $(basename "$dmg")  $(du -h "$dmg" | cut -f1 | xargs)"
  echo "    $(basename "$zip")  $(du -h "$zip" | cut -f1 | xargs)"
done

echo "\n==> SHA-256"
assets=("$dmg_prefix-AppleSilicon.dmg" "$dmg_prefix-Intel.dmg" Nearo-$VERSION-AppleSilicon.zip Nearo-$VERSION-Intel.zip)
(cd "$DIST" && shasum -a 256 $assets | tee "SHA256SUMS-$VERSION.txt")

if [[ "${1:-}" == "--publish" ]]; then
  notes="$DIST/notes-$VERSION.md"
  [[ -f "$notes" ]] || { echo "Missing $notes" >&2; exit 1; }
  body="$BUILD/body.md"
  {
    cat "$notes"
    print -- "\n<!-- nearo:install -->\n\n---\n"
    print -- "### ⬇️ Install\n"
    print -- "**Download the disk image for your Mac:**"
    print -- "- Apple Silicon (M1/M2/M3/M4): \`Nearo-AppleSilicon.dmg\`"
    print -- "- Intel: \`Nearo-Intel.dmg\`\n"
    print -- "Not sure which you have? Apple menu → **About This Mac** → **Chip** (Apple Silicon) or **Processor** (Intel). Nearo requires macOS 15 Sequoia or later.\n"
    print -- "Drag Nearo into Applications. For later updates, choose Check for Updates in Nearo."
    print -- "Checksums are in \`SHA256SUMS-$VERSION.txt\`."
  } > "$body"

  scripts/update-manifest.sh "v$VERSION" "$notes" "$DIST"
  echo "\n==> Publishing v$VERSION"
  gh release create "v$VERSION" --repo anwarulislam/nearo --verify-tag \
    "${assets[@]/#/$DIST/}" "$DIST/latest.json" "$DIST/SHA256SUMS-$VERSION.txt" \
    --title "Nearo $VERSION" --notes-file "$body"
fi
