#!/usr/bin/env bash
#
# setup-refs.sh — clone (or update) the KOReader source trees this repo's
# patches/plugins are developed against, into a local `_ref/` directory for
# LSP code navigation and reference. `_ref/` is git-ignored.
#
# Versions come from plugins/manifest.yml; there is nothing to edit here on
# a target bump.
#
# Works on Linux and macOS. Re-running updates existing clones in place.
#
# Usage:
#   scripts/setup-refs.sh            # clone/update all refs
#   REF_DIR=/somewhere scripts/setup-refs.sh   # override target dir

set -euo pipefail

# Resolve the repo root so the script works from any cwd.
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
REF_DIR="${REF_DIR:-${REPO_ROOT}/_ref}"
MANIFEST="${REPO_ROOT}/plugins/manifest.yml"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: '$1' is required but not installed." >&2
    exit 1
  }
}

require git
require yq

if [ ! -f "$MANIFEST" ]; then
  echo "error: manifest not found: $MANIFEST" >&2
  exit 1
fi

KO_VER="$(yq '.targets[0].koreader' "$MANIFEST")"
if [ -z "$KO_VER" ] || [ "$KO_VER" = "null" ]; then
  echo "error: manifest target 0 has no koreader version" >&2
  exit 1
fi

# Pin every tree to the first manifest target, so "written against <version>"
# can be checked against the source actually on disk. KOReader's git tag is its
# manifest version prefixed with "v"; each plugin tree is named after the last
# path segment of its repo, which is what .luarc.example.json expects.
REPOS=( "koreader|https://github.com/koreader/koreader.git|v${KO_VER}" )
while IFS=$'\t' read -r repo tag; do
  REPOS+=( "${repo##*/}|https://github.com/${repo}.git|${tag}" )
done < <(yq '.targets[0].plugins[] | [.repo, .tag] | @tsv' "$MANIFEST")

mkdir -p "$REF_DIR"

# Shallow clones keep these large trees small; we only need the source for
# navigation, not full history.
for entry in "${REPOS[@]}"; do
  IFS='|' read -r name url ref <<<"$entry"
  dest="${REF_DIR}/${name}"

  echo "==> ${name} @ ${ref}"
  if [ -d "${dest}/.git" ]; then
    git -C "$dest" fetch --depth 1 origin tag "$ref"
    git -C "$dest" checkout -q -f --detach "$ref"
  else
    git clone --depth 1 --branch "$ref" "$url" "$dest"
  fi
done

# Seed the LSP config from the template (git-ignored). Don't clobber an
# existing .luarc.json, which may carry local customizations.
EXAMPLE="${REPO_ROOT}/.luarc.example.json"
LUARC="${REPO_ROOT}/.luarc.json"
if [ -f "$LUARC" ]; then
  echo "==> .luarc.json already exists; leaving it untouched"
elif [ -f "$EXAMPLE" ]; then
  echo "==> Creating .luarc.json from .luarc.example.json"
  cp "$EXAMPLE" "$LUARC"
fi

echo
echo "Done. References are in: ${REF_DIR}"
