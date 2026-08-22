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

for cmd in gh jq unzip zip sha256sum; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "error: required tool not installed: $cmd" >&2
    exit 1
  fi
done

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

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

# GitHub rewrites spaces in release asset names to dots, which would leave the
# filename recorded inside the .sha256 unverifiable against the asset users
# actually download. Do that substitution here so the local name, the uploaded
# name and the checksum all agree. VERSIONS.txt keeps the readable codename.
BUNDLE_NAME="koreader-configs-${RELEASE_TAG}-koreader${KO_VER}-${CODENAME// /.}"
STAGING="$OUT_DIR/staging/$BUNDLE_NAME"

mkdir -p "$STAGING/plugins"
cp -R "$REPO_ROOT/icons" "$STAGING/icons"
cp -R "$REPO_ROOT/patches" "$STAGING/patches"
cp -R "$REPO_ROOT/settings" "$STAGING/settings"

{
  echo "koreader-configs $RELEASE_TAG for KOReader $KO_VER ($CODENAME)"
} > "$STAGING/VERSIONS.txt"

i=0
while [ "$i" -lt "$PLUGIN_COUNT" ]; do
  repo="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].repo")"
  tag="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].tag")"
  install_dir="$(echo "$TARGET_JSON" | jq -r ".plugins[$i].install_dir")"

  echo "==> fetching $repo @ $tag" >&2
  tmp="$(mktemp -d "$SCRATCH/XXXXXX")"
  gh release download "$tag" --repo "$repo" --pattern '*.zip' --dir "$tmp"

  zips=( "$tmp"/*.zip )
  if [ ${#zips[@]} -ne 1 ]; then
    echo "error: expected exactly one .zip in $repo@$tag, found ${#zips[@]}" >&2
    exit 1
  fi

  extract="$(mktemp -d "$SCRATCH/XXXXXX")"
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
  echo "${repo}@${tag}" >> "$STAGING/VERSIONS.txt"

  i=$((i + 1))
done

if [ ! -f "$REPO_ROOT/INSTALL.md" ]; then
  echo "error: $REPO_ROOT/INSTALL.md not found" >&2
  exit 1
fi
cp "$REPO_ROOT/INSTALL.md" "$STAGING/INSTALL.txt"

# zip updates an existing archive in place rather than replacing it, so a
# rebuild at the same tag would merge into the previous bundle and keep files
# that are no longer staged. CI always starts on a clean runner; local builds
# do not.
rm -f "$OUT_DIR/$BUNDLE_NAME.zip"
(
  cd "$OUT_DIR/staging"
  zip -qr "../$BUNDLE_NAME.zip" "$BUNDLE_NAME"
)
(
  cd "$OUT_DIR"
  sha256sum "$BUNDLE_NAME.zip" > "$BUNDLE_NAME.zip.sha256"
)

echo "$BUNDLE_NAME"
