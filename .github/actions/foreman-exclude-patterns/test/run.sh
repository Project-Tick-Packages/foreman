#!/usr/bin/env bash
# Smoke test for the foreman-exclude-patterns composite action's
# `compute` step. Re-implements the step inline so we can run it
# locally (or in a `bash-unit` job) without GitHub Actions runtime.
#
# Usage: ./run.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$(mktemp)"
trap 'rm -f "$out"' EXIT

compute() {
  local PLAN_JSON="${1:-}"
  if [[ -z "$PLAN_JSON" ]]; then
    PLAN_JSON='{}'
  fi
  GITHUB_OUTPUT="$out"
  : > "$GITHUB_OUTPUT"
  local patterns_json count rspec_args ctest_regex gtest_filter

  if ! patterns_json="$(printf '%s' "$PLAN_JSON" | jq -ce '.quarantined_tests // []' 2>/dev/null)"; then
    patterns_json='[]'
  fi
  count="$(printf '%s' "$patterns_json" | jq 'length' 2>/dev/null || echo 0)"
  rspec_args=""
  ctest_regex=""
  gtest_filter=""

  if [[ "$count" -gt 0 ]]; then
    rspec_args="$(printf '%s' "$patterns_json" \
      | jq -r 'map("--exclude-pattern \u0027" + . + "\u0027") | join(" ")')"
    ctest_regex="$(printf '%s' "$patterns_json" \
      | jq -r 'map("(" + . + ")") | join("|")')"
    gtest_filter="-$(printf '%s' "$patterns_json" \
      | jq -r 'join(":")')"
  fi

  {
    echo "patterns_json=$patterns_json"
    echo "rspec_args=$rspec_args"
    echo "ctest_regex=$ctest_regex"
    echo "gtest_filter=$gtest_filter"
    echo "count=$count"
  } >> "$GITHUB_OUTPUT"
}

assert_output() {
  local key="$1" expected="$2"
  local got
  got="$(grep "^$key=" "$out" | head -1 | cut -d= -f2-)"
  if [[ "$got" != "$expected" ]]; then
    echo "FAIL: $key — expected [$expected] got [$got]"
    exit 1
  fi
}

echo "--- empty plan"
compute '{}'
assert_output count 0
assert_output rspec_args ""
assert_output ctest_regex ""

echo "--- two patterns"
compute '{"quarantined_tests":["spec/a.rb:1","spec/flake.rb"]}'
assert_output count 2
assert_output rspec_args "--exclude-pattern 'spec/a.rb:1' --exclude-pattern 'spec/flake.rb'"
assert_output ctest_regex "(spec/a.rb:1)|(spec/flake.rb)"
assert_output gtest_filter "-spec/a.rb:1:spec/flake.rb"

echo "--- malformed plan tolerated"
compute 'not json'
assert_output count 0

echo "ALL OK"
