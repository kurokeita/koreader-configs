#!/usr/bin/env bash
#
# build-release.sh — build a release bundle locally, the same way CI does.
#
# Thin wrapper around .github/scripts/parse-manifest.sh and
# .github/scripts/build-bundle.sh, the two scripts .github/workflows/release.yml
# runs. No build logic lives here, so a local bundle matches a released one.
#
# Versions come from plugins/manifest.yml; there is nothing to edit here on a
# target bump.
#
# Downloads the pinned plugin releases from GitHub, so this needs network access
# and an authenticated `gh`. It only reads: nothing is tagged or published.
#
# Usage:
#   scripts/build-release.sh                      # target 0, named v0.0.0-local
#   RELEASE_TAG=v0.4.0 scripts/build-release.sh   # name it like a real release
#   TARGET_INDEX=1 scripts/build-release.sh       # a later manifest target
#   OUT_DIR=/tmp/out scripts/build-release.sh     # write somewhere else

set -euo pipefail

# Resolve the repo root so the script works from any cwd.
REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
MANIFEST="${REPO_ROOT}/plugins/manifest.yml"
OUT_DIR="${OUT_DIR:-${REPO_ROOT}/dist}"
TARGET_INDEX="${TARGET_INDEX:-0}"
# A test build should never be mistakable for a real one, so default to a tag
# that cannot exist upstream rather than to the latest real tag.
RELEASE_TAG="${RELEASE_TAG:-v0.0.0-local}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: '$1' is required but not installed." >&2
    exit 1
  }
}

require git
require jq
require gh

# build-bundle.sh checks its own tools (gh, jq, unzip, zip, sha256sum) but not
# whether gh can actually reach the releases, which fails much later.
if ! gh auth status >/dev/null 2>&1; then
  echo "error: 'gh' is not authenticated; run 'gh auth login'." >&2
  exit 1
fi

if ! TARGET_JSON="$(
  bash "${REPO_ROOT}/.github/scripts/parse-manifest.sh" "$MANIFEST" \
    | jq -ce ".[${TARGET_INDEX}]"
)"; then
  echo "error: manifest has no target at index ${TARGET_INDEX}" >&2
  exit 1
fi

KO_VER="$(echo "$TARGET_JSON" | jq -r '.koreader')"
CODENAME="$(echo "$TARGET_JSON" | jq -r '.codename')"

# build-bundle.sh moves each plugin folder into the staging tree and fails on a
# collision, so a leftover tree from an earlier run of the same tag would break
# the rebuild rather than be overwritten.
rm -rf "${OUT_DIR}/staging"
mkdir -p "$OUT_DIR"

echo "==> building ${RELEASE_TAG} for KOReader ${KO_VER} (${CODENAME})"

BUNDLE_NAME="$(
  env TARGET_JSON="$TARGET_JSON" \
      RELEASE_TAG="$RELEASE_TAG" \
      REPO_ROOT="$REPO_ROOT" \
      OUT_DIR="$OUT_DIR" \
      bash "${REPO_ROOT}/.github/scripts/build-bundle.sh"
)"

echo
echo "==> ${BUNDLE_NAME}"
cat "${OUT_DIR}/staging/${BUNDLE_NAME}/VERSIONS.txt"

echo
echo "Bundle:   ${OUT_DIR}/${BUNDLE_NAME}.zip"
echo "Checksum: ${OUT_DIR}/${BUNDLE_NAME}.zip.sha256"
echo "Staging:  ${OUT_DIR}/staging/${BUNDLE_NAME}/"
