#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 <path-to-manifest.yml>" >&2
  exit 2
}

[ $# -eq 1 ] || usage
MANIFEST="$1"

if [ ! -f "$MANIFEST" ]; then
  echo "error: manifest not found: $MANIFEST" >&2
  exit 1
fi

if ! command -v yq >/dev/null 2>&1; then
  echo "error: yq is required but not installed" >&2
  exit 1
fi

target_count="$(yq '.targets | length' "$MANIFEST")"
if [ "$target_count" = "null" ] || [ "$target_count" -lt 1 ]; then
  echo "error: manifest has no targets" >&2
  exit 1
fi

i=0
while [ "$i" -lt "$target_count" ]; do
  for field in koreader codename; do
    val="$(yq ".targets[$i].$field // \"\"" "$MANIFEST")"
    if [ -z "$val" ] || [ "$val" = "null" ]; then
      echo "error: target index $i missing required field: $field" >&2
      exit 1
    fi
  done

  plugin_count="$(yq ".targets[$i].plugins | length" "$MANIFEST")"
  if [ "$plugin_count" = "null" ] || [ "$plugin_count" -lt 1 ]; then
    echo "error: target index $i has no plugins" >&2
    exit 1
  fi

  j=0
  while [ "$j" -lt "$plugin_count" ]; do
    for field in repo tag install_dir; do
      val="$(yq ".targets[$i].plugins[$j].$field // \"\"" "$MANIFEST")"
      if [ -z "$val" ] || [ "$val" = "null" ]; then
        echo "error: target $i plugin $j missing required field: $field" >&2
        exit 1
      fi
    done
    j=$((j + 1))
  done

  i=$((i + 1))
done

yq -o=json -I=0 '.targets' "$MANIFEST"
