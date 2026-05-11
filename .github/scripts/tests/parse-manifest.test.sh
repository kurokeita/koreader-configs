#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/../parse-manifest.sh"
FIXTURES="$HERE/fixtures"
PASS=0
FAIL=0

assert() {
  local name="$1"
  shift
  if "$@"; then
    echo "  ok  - $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL - $name"
    FAIL=$((FAIL + 1))
  fi
}

test_valid_outputs_json() {
  local out
  out="$(bash "$SCRIPT" "$FIXTURES/manifest-valid.yml")"
  echo "$out" | grep -q '"koreader":"2026.03"' \
    && echo "$out" | grep -q '"codename":"Snowflake"' \
    && echo "$out" | grep -q '"repo":"joshuacant/ProjectTitle"' \
    && echo "$out" | grep -q '"repo":"AndyHazz/bookends.koplugin"'
}

test_valid_exit_zero() {
  bash "$SCRIPT" "$FIXTURES/manifest-valid.yml" >/dev/null
}

test_missing_codename_fails() {
  ! bash "$SCRIPT" "$FIXTURES/manifest-missing-codename.yml" >/dev/null 2>&1
}

test_missing_codename_message() {
  { bash "$SCRIPT" "$FIXTURES/manifest-missing-codename.yml" 2>&1 || true; } \
    | grep -qi 'codename'
}

test_no_plugins_fails() {
  ! bash "$SCRIPT" "$FIXTURES/manifest-no-plugins.yml" >/dev/null 2>&1
}

test_missing_file_fails() {
  ! bash "$SCRIPT" "$FIXTURES/does-not-exist.yml" >/dev/null 2>&1
}

test_missing_plugin_tag_fails() {
  ! bash "$SCRIPT" "$FIXTURES/manifest-missing-plugin-tag.yml" >/dev/null 2>&1
}

test_missing_plugin_tag_message() {
  { bash "$SCRIPT" "$FIXTURES/manifest-missing-plugin-tag.yml" 2>&1 || true; } \
    | grep -qi 'tag'
}

assert "valid manifest produces expected JSON" test_valid_outputs_json
assert "valid manifest exits 0" test_valid_exit_zero
assert "missing codename fails" test_missing_codename_fails
assert "missing codename message mentions field" test_missing_codename_message
assert "no plugins fails" test_no_plugins_fails
assert "missing file fails" test_missing_file_fails
assert "missing plugin tag fails" test_missing_plugin_tag_fails
assert "missing plugin tag message mentions field" test_missing_plugin_tag_message

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
