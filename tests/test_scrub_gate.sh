#!/usr/bin/env bash
# The scrub gate must catch employer tokens without tripping on the OS username.
# $HOME is /home/capra_vhr, so a bare `grep -i <company>` matches every absolute
# path in every file and is useless.

_scrub_fixture() {
  local dir="$1" content="$2"
  mkdir -p "$dir"
  ( cd "$dir" && git init -q . && printf '%s\n' "$content" > f.txt \
    && git add f.txt && git -c user.email=t@t -c user.name=t commit -qm x )
}

test_gate_ignores_the_os_username() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  _scrub_fixture "$tmp/r" "config lives in /home/capra_vhr/.config and id capra_vhr.battery"

  if "$REPO_ROOT/bin/scrub-gate" "$tmp/r" >/dev/null 2>&1; then
    pass "gate ignores the OS username and home paths"
  else
    fail "gate ignores the OS username and home paths" "false positive on capra_vhr"
  fi
}

test_gate_catches_employer_token_in_tree() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  _scrub_fixture "$tmp/r" "builds run on example-monorepo nightly"

  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches example-monorepo in the tree (exit status)"
  else
    fail "gate catches example-monorepo in the tree (exit status)" "gate passed a real token"
  fi
  assert_contains "$out" "employer tokens" "gate names the tree finding"
  assert_contains "$out" "example-monorepo" "gate reports the matched token (tree)"
}

test_gate_catches_employer_token_only_in_history() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  _scrub_fixture "$tmp/r" "reachable on ExampleVPN only"
  ( cd "$tmp/r" && printf 'clean\n' > f.txt \
    && git add f.txt && git -c user.email=t@t -c user.name=t commit -qm scrub )

  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches a token only present in history (exit status)"
  else
    fail "gate catches a token only present in history (exit status)" "clean tip hid a dirty history"
  fi
  assert_contains "$out" "employer tokens" "gate names the history finding"
  assert_contains "$out" "ExampleVPN" "gate reports the matched token (history)"
}

test_gate_catches_employer_token_in_untracked_file() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  _scrub_fixture "$tmp/r" "clean tracked content"
  printf 'staging deploys go through example-stage\n' > "$tmp/r/untracked.txt"

  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches an employer token in an untracked file (exit status)"
  else
    fail "gate catches an employer token in an untracked file (exit status)" "untracked file with a token passed the gate"
  fi
  assert_contains "$out" "employer tokens" "gate names the untracked finding"
  assert_contains "$out" "example-stage" "gate reports the matched token (untracked)"
}
