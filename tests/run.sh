#!/usr/bin/env bash
# Plain bash test harness. Each tests/test_*.sh defines test_* functions and is
# sourced with REPO_ROOT, assert_eq, assert_contains, pass and fail available.
set -Euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }

fail() {
  FAILED=$((FAILED + 1))
  printf '  FAIL %s\n' "$1" >&2
  [[ $# -gt 1 ]] && printf '       %s\n' "$2" >&2
  return 0
}

assert_eq() {
  local want="$1" got="$2" what="$3"
  if [[ "$want" == "$got" ]]; then
    pass "$what"
  else
    fail "$what" "want: [$want]  got: [$got]"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" what="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$what"
  else
    fail "$what" "[$needle] not found in output"
  fi
}

for suite in "$REPO_ROOT"/tests/test_*.sh; do
  printf '%s\n' "--- $(basename "$suite") ---"
  # shellcheck disable=SC1090
  source "$suite"
  while IFS= read -r fn; do
    "$fn"
  done < <(declare -F | awk '{print $3}' | grep '^test_' | sort)
  # Unset so the next suite's function list is clean.
  while IFS= read -r fn; do unset -f "$fn"; done \
    < <(declare -F | awk '{print $3}' | grep '^test_')
done

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
