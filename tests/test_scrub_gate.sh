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

  if "$REPO_ROOT/bin/scrub-gate" "$tmp/r" >/dev/null 2>&1; then
    fail "gate catches example-monorepo in the tree" "gate passed a real token"
  else
    pass "gate catches example-monorepo in the tree"
  fi
}

test_gate_catches_employer_token_only_in_history() {
  local tmp; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' RETURN
  _scrub_fixture "$tmp/r" "reachable on ExampleVPN only"
  ( cd "$tmp/r" && printf 'clean\n' > f.txt \
    && git add f.txt && git -c user.email=t@t -c user.name=t commit -qm scrub )

  if "$REPO_ROOT/bin/scrub-gate" "$tmp/r" >/dev/null 2>&1; then
    fail "gate catches a token only present in history" "clean tip hid a dirty history"
  else
    pass "gate catches a token only present in history"
  fi
}
