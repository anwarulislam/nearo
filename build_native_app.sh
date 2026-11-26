#!/bin/zsh
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$PWD"

echo "Building Nearo for macOS..."

xcodebuild -project Nearo.xcodeproj -scheme Nearo -configuration Release \
  -derivedDataPath "$ROOT/build" -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build -quiet

mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Nearo.app"
cp -r "$ROOT/build/Build/Products/Release/Nearo.app" "$ROOT/dist/Nearo.app"

# Fix framework symlinks if present
FRAMEWORK="$ROOT/dist/Nearo.app/Contents/Frameworks/MediaRemoteAdapter.framework"
if [[ -d "$FRAMEWORK" ]]; then
  cd "$FRAMEWORK"
  rm -rf MediaRemoteAdapter Resources Current Versions/Current
  ln -s A Versions/Current
  ln -s Versions/Current/MediaRemoteAdapter MediaRemoteAdapter
  ln -s Versions/Current/Resources Resources
  cd "$ROOT"
fi

# Ad-hoc code sign the bundle
codesign --force --deep --sign - "$ROOT/dist/Nearo.app"
codesign --verify --deep --strict "$ROOT/dist/Nearo.app"

echo "Build successful: $ROOT/dist/Nearo.app"
