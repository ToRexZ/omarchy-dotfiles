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
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _scrub_fixture "$tmp/r" "config lives in /home/capra_vhr/.config and id capra_vhr.battery"

  if "$REPO_ROOT/bin/scrub-gate" "$tmp/r" >/dev/null 2>&1; then
    pass "gate ignores the OS username and home paths"
  else
    fail "gate ignores the OS username and home paths" "false positive on capra_vhr"
  fi
}

test_gate_catches_employer_token_in_tree() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
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
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
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
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
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

# --- Fix round 1: the gate used to fail open -------------------------------
#
# `git grep ... | grep -q .` under `set -o pipefail` reports CLEAN on a dirty
# repo: `grep -q` exits at the first match and closes the pipe, `git grep` is
# killed by SIGPIPE (141), pipefail makes 141 the pipeline status, and the `if`
# is false. Measured on this repo before the fix: 59 real tree hits,
# `PIPESTATUS=141 0`, `bin/scrub-gate .` exit 0, 20/20 runs.
#
# Whether the race is lost depends on how much the producer still has to write
# when the consumer leaves: everything that already fits in the 64 KiB pipe
# buffer is written without blocking, so a small fixture never reproduces it
# (measured: 200 files / ~8 KB of matches, 20/20 caught). The fixture below is
# sized past the buffer on purpose, and loses the race 10/10 against the old
# piped form.

_scrub_big_fixture() {
  local dir="$1" i line=""
  for i in $(seq 1 12); do line+="builds run on example-monorepo nightly "; done
  mkdir -p "$dir"
  (
    cd "$dir" && git init -q .
    for i in $(seq 1 400); do printf '%s %s\n' "$line" "$i" > "f$i.txt"; done
    git add -A && git -c user.email=t@t -c user.name=t commit -qm bulk
  ) >/dev/null
}

test_gate_does_not_fail_open_on_a_many_match_tree() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _scrub_big_fixture "$tmp/r"

  local what="gate does not fail open on a tree with many matches"
  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "$what (exit status)"
  else
    fail "$what (exit status)" "400 matching files and the gate reported clean"
  fi

  # Not just "it noticed something": every match has to survive to the report,
  # which is the part SIGPIPE truncated.
  local reported want
  reported="$(printf '%s\n' "$out" | grep -c 'example-monorepo' || true)"
  want=400
  if [[ "$reported" -ge "$want" ]]; then
    pass "$what (all $want matches reported)"
  else
    fail "$what (all $want matches reported)" "reported $reported of $want"
  fi
}

test_gate_does_not_fail_open_on_a_many_match_history() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _scrub_big_fixture "$tmp/r"
  # Scrub the tree so only the history is dirty -- and leave the history large,
  # so the `git log -p --all | grep | grep -q .` chain has the same race.
  ( cd "$tmp/r" && git rm -q -r . >/dev/null && printf 'clean\n' > ok.txt \
    && git add ok.txt && git -c user.email=t@t -c user.name=t commit -qm scrub ) >/dev/null

  local what="gate does not fail open on a large dirty history"
  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "$what (exit status)"
  else
    fail "$what (exit status)" "clean tip hid a 400-file dirty history"
  fi
  assert_contains "$out" "employer tokens in history" "gate names the history finding (large)"
}

test_gate_verdict_agrees_with_a_direct_capture_on_this_repo() {
  # The reviewer's witness: a real repo, with real content, where the piped
  # form was measured reporting clean against 59 hits. The gate's verdict has
  # to agree with a capture-and-count that cannot race -- in both directions,
  # so this keeps working if the repo is ever genuinely scrubbed.
  local what="gate verdict agrees with a direct capture on this repo"
  local tokens
  tokens="$(sed -n "s/^TOKENS='\(.*\)'$/\1/p" "$REPO_ROOT/bin/scrub-gate")"
  if [[ -z "$tokens" ]]; then
    fail "$what" "could not read TOKENS out of bin/scrub-gate"
    return
  fi

  local tree untracked history dirty=0
  tree="$(git -C "$REPO_ROOT" grep -IinE "$tokens" -- . 2>/dev/null)" || true
  untracked="$(git -C "$REPO_ROOT" ls-files --others --exclude-standard -z \
    | xargs -0 -r grep -HIinE "$tokens" -- 2>/dev/null)" || true
  history="$(git -C "$REPO_ROOT" log -p --all 2>/dev/null | grep -inE "$tokens")" || true
  [[ -n "$tree" || -n "$untracked" || -n "$history" ]] && dirty=1

  local status
  "$REPO_ROOT/bin/scrub-gate" "$REPO_ROOT" >/dev/null 2>&1
  status=$?

  if [[ ( "$dirty" -eq 1 && "$status" -ne 0 ) || ( "$dirty" -eq 0 && "$status" -eq 0 ) ]]; then
    pass "$what"
  else
    local n; n="$(printf '%s' "$tree" | grep -c . || true)"
    fail "$what" "direct capture: dirty=$dirty ($n tree hits), gate exit: $status"
  fi
}

# --- Fix round 2: the widened token list ------------------------------------
#
# example_nav, example_hmi, PROJ-4268, partnerco and ci-build-agent-2 were all real
# employer content found in the prbuilds plugin, and all five passed the
# narrow list cleanly. They are now tokens. The obvious "fix" -- a bare
# `company_` prefix -- is the one thing that must never be added: $HOME is
# /home/capra_vhr, so it would match every absolute path in every repo.
# test_gate_ignores_the_os_username above is what pins that, and it has to keep
# passing alongside these.

test_gate_catches_a_newly_added_token() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _scrub_fixture "$tmp/r" "the ros package example_nav and issue PROJ-4268 on ci-build-agent-2 with a partnerco lift"

  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches the fix-round-2 tokens (exit status)"
  else
    fail "gate catches the fix-round-2 tokens (exit status)" "widened tokens still pass the gate"
  fi
  local t
  for t in example_nav PROJ-4268 ci-build-agent-2 partnerco; do
    assert_contains "$out" "$t" "gate reports the matched token ($t)"
  done
}

test_gate_has_no_bare_company_underscore_token() {
  # Read from the script rather than asserted by behaviour, because a bare
  # `company_` would still pass every fixture above -- it only shows up as a
  # storm of false positives on real repos full of /home/capra_vhr paths.
  local what="gate's token list has no bare company_ prefix"
  local tokens
  tokens="$(sed -n "s/^TOKENS='\(.*\)'$/\1/p" "$REPO_ROOT/bin/scrub-gate")"
  if [[ -z "$tokens" ]]; then
    fail "$what" "could not read TOKENS out of bin/scrub-gate"
    return
  fi

  local bad="" t
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    # Anything that a /home/capra_vhr path would match: capra_ followed by
    # nothing, or by a character class / quantifier rather than a literal name.
    [[ "$t" == "company_" ]] && bad+="[$t] "
    [[ "$t" == company_[.\[\(*+?] ]] && bad+="[$t] "
  done < <(printf '%s\n' "$tokens" | tr '|' '\n')

  if [[ -z "$bad" ]]; then
    pass "$what"
  else
    fail "$what" "these would match the OS username: $bad"
  fi
}
