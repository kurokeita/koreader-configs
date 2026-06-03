#!/usr/bin/env bash
#
# setup-refs.sh — clone (or update) the KOReader source trees this repo's
# patches/plugins are developed against, into a local `_ref/` directory for
# LSP code navigation and reference. `_ref/` is git-ignored.
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

# Shallow clones keep these large trees small; we only need the source for
# navigation, not full history. name|url|branch (branch empty = default).
REPOS=(
  "koreader|https://github.com/koreader/koreader.git|"
  "ProjectTitle|https://github.com/joshuacant/ProjectTitle.git|"
  "bookends.koplugin|https://github.com/AndyHazz/bookends.koplugin.git|"
)

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: '$1' is required but not installed." >&2
    exit 1
  }
}

require git

mkdir -p "$REF_DIR"

for entry in "${REPOS[@]}"; do
  IFS='|' read -r name url branch <<<"$entry"
  dest="${REF_DIR}/${name}"

  if [ -d "${dest}/.git" ]; then
    echo "==> Updating ${name}"
    git -C "$dest" fetch --depth 1 origin
    # Fast-forward the checked-out branch to the fetched tip.
    git -C "$dest" reset --hard "@{upstream}" 2>/dev/null \
      || git -C "$dest" reset --hard FETCH_HEAD
  else
    echo "==> Cloning ${name}"
    if [ -n "$branch" ]; then
      git clone --depth 1 --branch "$branch" "$url" "$dest"
    else
      git clone --depth 1 "$url" "$dest"
    fi
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
