#!/usr/bin/env bash
# Write the update feed alongside the ZIPs that will be attached to this release.
set -euo pipefail

[[ $# == 3 && "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Usage: $0 vMAJOR.MINOR.PATCH notes.md artifacts-directory" >&2
  exit 2
}
tag="$1"
notes=$(awk '/<!-- nearo:install -->/{exit} {print}' "$2")
directory="$3"
version="${tag#v}"

archive() {
  local name="Nearo-$version-$1.zip"
  local size digest
  size=$(wc -c < "$directory/$name")
  digest=$(shasum -a 256 "$directory/$name")
  jq -n --arg name "$name" --argjson size "$size" --arg sha256 "${digest%% *}" \
    '{name: $name, size: $size, sha256: $sha256}'
}

silicon=$(archive AppleSilicon)
intel=$(archive Intel)
jq -n --arg version "$version" --arg tag "$tag" --arg notes "$notes" \
  --argjson silicon "$silicon" --argjson intel "$intel" \
  '{version: $version, tag: $tag, notes: $notes, archives: {AppleSilicon: $silicon, Intel: $intel}}' \
  > "$directory/latest.json"
