#!/usr/bin/env bash
set -euo pipefail

require_var() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "error: required env var not set: $name" >&2
    exit 2
  fi
}

require_var TARGET_JSON
require_var RELEASE_TAG
require_var REPO_ROOT
require_var OUT_DIR

for cmd in gh jq unzip zip shasum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required tool not installed: $cmd" >&2
    exit 1
  fi
done

KO_VER="$(echo "$TARGET_JSON" | jq -r '.koreader')"
CODENAME="$(echo "$TARGET_JSON" | jq -r '.codename')"
PLUGIN_COUNT="$(echo "$TARGET_JSON" | jq '.plugins | length')"

if [ -z "$KO_VER" ] || [ "$KO_VER" = "null" ]; then
  echo "error: target JSON missing koreader" >&2
  exit 1
fi
if [ -z "$CODENAME" ] || [ "$CODENAME" = "null" ]; then
  echo "error: target JSON missing codename" >&2
  exit 1
fi

BUNDLE_NAME="koreader-configs-${RELEASE_TAG}-koreader${KO_VER}-${CODENAME}"
STAGING="$OUT_DIR/staging/$BUNDLE_NAME"

mkdir -p "$STAGING/plugins"
cp -R "$REPO_ROOT/icons" "$STAGING/icons"
cp -R "$REPO_ROOT/patches" "$STAGING/patches"

i=0
while [ "$i" -lt "$PLUGIN_COUNT" ]; do
  repo="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].repo")"
  tag="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].tag")"
  install_dir="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].install_dir")"

  echo "==> fetching $repo @ $tag"
  tmp="$(mktemp -d)"
  gh release download "$tag" --repo "$repo" --pattern '*.zip' --dir "$tmp"

  zips=( "$tmp"/*.zip )
  if [ ${#zips[@]} -ne 1 ]; then
    echo "error: expected exactly one .zip in $repo@$tag, found ${#zips[@]}" >&2
    exit 1
  fi

  extract="$(mktemp -d)"
  unzip -q "${zips[0]}" -d "$extract"

  shopt -s nullglob
  koplugins=( "$extract"/*.koplugin )
  shopt -u nullglob
  if [ ${#koplugins[@]} -ne 1 ]; then
    echo "error: expected one *.koplugin folder in $repo@$tag, found ${#koplugins[@]}" >&2
    exit 1
  fi

  src="${koplugins[0]}"
  if [ "$(basename "$src")" != "$install_dir" ]; then
    mv "$src" "$extract/$install_dir"
    src="$extract/$install_dir"
  fi

  mv "$src" "$STAGING/plugins/$install_dir"
  rm -rf "$tmp" "$extract"

  i=$((i + 1))
done

{
  echo "koreader-configs $RELEASE_TAG for KOReader $KO_VER ($CODENAME)"
  i=0
  while [ "$i" -lt "$PLUGIN_COUNT" ]; do
    repo="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].repo")"
    tag="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].tag")"
    echo "${repo}@${tag}"
    i=$((i + 1))
  done
} > "$STAGING/VERSIONS.txt"

cp "$REPO_ROOT/INSTALL.md" "$STAGING/INSTALL.txt"

(
  cd "$OUT_DIR/staging"
  zip -qr "../$BUNDLE_NAME.zip" "$BUNDLE_NAME"
)
(
  cd "$OUT_DIR"
  shasum -a 256 "$BUNDLE_NAME.zip" > "$BUNDLE_NAME.zip.sha256"
)

echo "$BUNDLE_NAME"
