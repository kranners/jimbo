#!/usr/bin/env bash
set -euo pipefail

pins="$(dirname "$0")/extensions.nix"
crx=$(mktemp)
trap 'rm -f "$crx"' EXIT

for id in $(sed -n 's/^ *id = "\([a-p]\{32\}\)";$/\1/p' "$pins"); do
  curl -fsSL -o "$crx" \
    "https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx3&prodversion=140&x=id%3D$id%26uc"
  version=$({ unzip -p "$crx" manifest.json 2>/dev/null || [ $? -eq 1 ]; } | jq -r .version)
  hash=$(nix hash file --sri --type sha256 "$crx")
  sed "/id = \"$id\"/,/hash = /{
    s/version = \".*\"/version = \"$version\"/
    s|hash = \".*\"|hash = \"$hash\"|
  }" "$pins" >"$pins.new"
  mv "$pins.new" "$pins"
done
