#!/usr/bin/env bash
# The scrub gate must catch employer tokens without tripping on the OS
# username. $HOME is /home/capra_vhr, so a bare `grep -i <company>` matches every
# absolute path in every file and is useless.
#
# NO EMPLOYER TOKEN IS WRITTEN DOWN IN THIS FILE.
#
# Every fixture string below is assembled at runtime around $_z, which is
# empty, exactly as bin/scrub-gate assembles its own TOKENS. A token you can't
# write down can't be tested -- but a token built from halves can be tested
# and still is not present as a string anywhere in this repository. That is
# what lets bin/scrub-gate scan with no exclusions at all: it has no reason to
# skip this file, so it doesn't, so there is no path-shaped hole to carry into
# the repos it is actually pointed at before they are published.
#
# Fix round 3 did this by pathspec instead (`:(exclude)bin/scrub-gate`,
# `:(exclude)tests/test_scrub_gate.sh`). Two tests below are what that round
# should have had: test_gate_catches_a_real_token_at_its_own_two_paths plants
# real tokens at those exact paths and asserts THOSE tokens are reported -- the
# earlier test of that name planted them and then only asserted on a third
# file, so it passed while the property in its name was false. And
# test_gate_source_holds_no_literal_token is the invariant that keeps the
# exclusion unnecessary rather than merely absent.
_z=''
TOK_MONO="example${_z}-monorepo"       # the ROS monorepo
TOK_WG="Example${_z}VPN"                # the WireGuard profile
TOK_STAGE="example${_z}-stage"         # a build environment
TOK_NAV="example${_z}_nav"             # a ROS package
TOK_KEY="PROJ${_z}-4268"              # a Jira issue key
TOK_AGENT="ci-build${_z}-agent-2" # a build agent
TOK_PARTNER="part${_z}nerco"                 # a partner brand
TOK_HOST="ci${_z}.example"     # the CI host
TOK_COMPANY="example${_z}org"     # the company name, run together

# The gate's own assembled regex. Read from the tool (`--print-tokens`) rather
# than sed'd out of its source or copied here: a second copy drifts, and the
# source no longer holds the list as a literal anyway.
_gate_tokens() { "$REPO_ROOT/bin/scrub-gate" --print-tokens; }

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
  _scrub_fixture "$tmp/r" "builds run on $TOK_MONO nightly"

  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches the ROS monorepo name in the tree (exit status)"
  else
    fail "gate catches the ROS monorepo name in the tree (exit status)" "gate passed a real token"
  fi
  assert_contains "$out" "employer tokens" "gate names the tree finding"
  assert_contains "$out" "$TOK_MONO" "gate reports the matched token (tree)"
}

test_gate_catches_employer_token_only_in_history() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _scrub_fixture "$tmp/r" "reachable on $TOK_WG only"
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
  assert_contains "$out" "$TOK_WG" "gate reports the matched token (history)"
}

test_gate_catches_employer_token_in_untracked_file() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _scrub_fixture "$tmp/r" "clean tracked content"
  printf 'staging deploys go through %s\n' "$TOK_STAGE" > "$tmp/r/untracked.txt"

  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches an employer token in an untracked file (exit status)"
  else
    fail "gate catches an employer token in an untracked file (exit status)" "untracked file with a token passed the gate"
  fi
  assert_contains "$out" "employer tokens" "gate names the untracked finding"
  assert_contains "$out" "$TOK_STAGE" "gate reports the matched token (untracked)"
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
  for i in $(seq 1 12); do line+="builds run on $TOK_MONO nightly "; done
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
  reported="$(printf '%s\n' "$out" | grep -c -- "$TOK_MONO" || true)"
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
  #
  # The direct capture applies no exclusion, because the gate applies none
  # either. Before fix round 4 the two had to be kept in step by hand, and a
  # separate test existed only to check they had not drifted; there is nothing
  # left to drift.
  local what="gate verdict agrees with a direct capture on this repo"
  local tokens
  tokens="$(_gate_tokens)"
  if [[ -z "$tokens" ]]; then
    fail "$what" "bin/scrub-gate --print-tokens produced nothing"
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
# The two extra ROS package names, the second Jira project key, the partner
# brand and the build agent were all real employer content found in the
# prbuilds plugin, and all five passed the narrow list cleanly. They are now
# tokens. The obvious "fix" -- a bare `company_` prefix -- is the one thing that
# must never be added: $HOME is /home/capra_vhr, so it would match every
# absolute path in every repo. test_gate_ignores_the_os_username above is what
# pins that, and it has to keep passing alongside these.

test_gate_catches_a_newly_added_token() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _scrub_fixture "$tmp/r" \
    "the ros package $TOK_NAV and issue $TOK_KEY on $TOK_AGENT with a $TOK_PARTNER lift"

  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches the fix-round-2 tokens (exit status)"
  else
    fail "gate catches the fix-round-2 tokens (exit status)" "widened tokens still pass the gate"
  fi
  local t
  for t in "$TOK_NAV" "$TOK_KEY" "$TOK_AGENT" "$TOK_PARTNER"; do
    assert_contains "$out" "$t" "gate reports the matched token ($t)"
  done
}

test_gate_has_no_bare_company_underscore_token() {
  # Read from the tool rather than asserted by behaviour, because a bare
  # `company_` would still pass every fixture above -- it only shows up as a
  # storm of false positives on real repos full of /home/capra_vhr paths.
  local what="gate's token list has no bare company_ prefix"
  local tokens
  tokens="$(_gate_tokens)"
  if [[ -z "$tokens" ]]; then
    fail "$what" "bin/scrub-gate --print-tokens produced nothing"
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

# --- Fix round 4 (Task 12): the gate must have no blind spot at all ---------
#
# Fix round 3 excluded bin/scrub-gate and tests/test_scrub_gate.sh by pathspec
# so the gate would stop matching its own token list. Two holes followed, both
# reproduced before this round: a real token at either of those paths, in ANY
# repo the gate is pointed at, returned exit 0; and the pathspec on the history
# scan silently dropped every empty commit's message, because a commit that
# touches no path survives no path filter.
#
# Both exclusions are gone. What replaced them is upstream of the scan: the
# repo no longer contains the tokens to match. The three tests below are the
# ones that make that an enforced property rather than a claim.

test_gate_source_holds_no_literal_token() {
  # The invariant that keeps the exclusion unnecessary. Every file the gate
  # ships with is scanned with the gate's OWN assembled regex; a single literal
  # token anywhere in bin/ or tests/ fails here, with the line, long before
  # anyone is tempted to reach for a pathspec again.
  local what="the gate's own source and fixtures hold no literal employer token"
  local tokens
  tokens="$(_gate_tokens)"
  if [[ -z "$tokens" ]]; then
    fail "$what" "bin/scrub-gate --print-tokens produced nothing"
    return
  fi

  local hits
  hits="$(grep -rnIiE "$tokens" "$REPO_ROOT/bin" "$REPO_ROOT/tests" 2>/dev/null)" || true
  if [[ -z "$hits" ]]; then
    pass "$what"
  else
    fail "$what" "$(printf '%s' "$hits" | head -3 | tr '\n' ' ')"
  fi
}

test_gate_catches_a_real_token_at_its_own_two_paths() {
  # The property fix round 3 claimed in a test name and never checked. A repo
  # whose ONLY employer content sits at bin/scrub-gate and
  # tests/test_scrub_gate.sh must still be refused, and each planted token must
  # be named in the report -- no third file to carry the verdict this time.
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  mkdir -p "$tmp/r/bin" "$tmp/r/tests"
  printf 'deploy target is %s\n' "$TOK_HOST" > "$tmp/r/bin/scrub-gate"
  printf 'owned by %s\n' "$TOK_COMPANY" > "$tmp/r/tests/test_scrub_gate.sh"
  ( cd "$tmp/r" && git init -q . \
      && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null

  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  local what="gate catches a real token at bin/scrub-gate and tests/test_scrub_gate.sh"
  if [[ "$status" -ne 0 ]]; then
    pass "$what (exit status)"
  else
    fail "$what (exit status)" "a repo whose only employer content is at those two paths passed the gate"
  fi
  assert_contains "$out" "bin/scrub-gate" "gate names the hit at bin/scrub-gate"
  assert_contains "$out" "$TOK_HOST" "gate reports the token planted at bin/scrub-gate"
  assert_contains "$out" "tests/test_scrub_gate.sh" "gate names the hit at tests/test_scrub_gate.sh"
  assert_contains "$out" "$TOK_COMPANY" "gate reports the token planted at tests/test_scrub_gate.sh"

  # Untracked, at the same two paths: the pathspec hid those too.
  local tmp2; tmp2="$(mktemp -d)"
  mkdir -p "$tmp2/r/bin"
  ( cd "$tmp2/r" && git init -q . && printf 'clean\n' > ok.txt && git add ok.txt \
      && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null
  printf 'deploy target is %s\n' "$TOK_HOST" > "$tmp2/r/bin/scrub-gate"
  if "$REPO_ROOT/bin/scrub-gate" "$tmp2/r" >/dev/null 2>&1; then
    fail "$what (untracked)" "an untracked token at bin/scrub-gate passed the gate"
  else
    pass "$what (untracked)"
  fi
  rm -rf "$tmp2"
}

test_gate_catches_a_token_in_a_commit_message() {
  # `git log -p --all -- .` narrowed the history scan to paths. An EMPTY commit
  # touches no path, so its message survived no filter and was dropped
  # wholesale -- and commit messages are exactly where a project or host name
  # leaks. A commit that touches only a formerly-excluded path was dropped the
  # same way, message and diff together.
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  mkdir -p "$tmp/r"
  (
    cd "$tmp/r" && git init -q .
    printf 'clean\n' > ok.txt && git add ok.txt
    git -c user.email=t@t -c user.name=t commit -qm seed
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "rollout to $TOK_HOST"
  ) >/dev/null

  local out status
  out="$("$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  local what="gate catches a token in an empty commit's message"
  if [[ "$status" -ne 0 ]]; then
    pass "$what (exit status)"
  else
    fail "$what (exit status)" "an empty commit carrying the token in its message passed the gate"
  fi
  assert_contains "$out" "employer tokens in history" "gate names the history finding (message)"
  assert_contains "$out" "$TOK_HOST" "gate reports the token from the commit message"

  # A commit whose only change is at one of the two formerly-excluded paths:
  # dropped by the pathspec, message and diff together.
  local tmp2; tmp2="$(mktemp -d)"
  mkdir -p "$tmp2/r/bin"
  (
    cd "$tmp2/r" && git init -q .
    printf 'clean\n' > ok.txt && git add ok.txt
    git -c user.email=t@t -c user.name=t commit -qm seed
    printf 'x\n' > bin/scrub-gate && git add bin/scrub-gate
    git -c user.email=t@t -c user.name=t commit -qm "point it at $TOK_WG"
    git rm -q bin/scrub-gate
    git -c user.email=t@t -c user.name=t commit -qm cleanup
  ) >/dev/null
  local out2
  out2="$("$REPO_ROOT/bin/scrub-gate" "$tmp2/r" 2>&1)" || true
  if [[ "$out2" == *"$TOK_WG"* ]]; then
    pass "gate catches a message on a commit that touches only bin/scrub-gate"
  else
    fail "gate catches a message on a commit that touches only bin/scrub-gate" \
      "the commit's message never reached the scan"
  fi
  rm -rf "$tmp2"
}
