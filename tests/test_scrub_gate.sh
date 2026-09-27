#!/usr/bin/env bash
# Tests for bin/scrub-gate.
#
# NO EMPLOYER TOKEN APPEARS IN THIS FILE, IN ANY FORM.
#
# Earlier rounds got close and stopped short. Round 3 hid the list from the
# scan with a pathspec, which put a hole in the tool itself. Round 4 replaced
# the pathspec with an empty-variable split, so the list no longer MATCHED --
# but every name was still here, in order, each one annotated with what it
# was. Matching and disclosure are different problems and only one of them was
# solved.
#
# So the list is gone from the repository entirely. Two consequences shape
# every test below:
#
#   Behaviour is tested with an INVENTED list, written to a temp file and
#   passed in with $SCRUB_GATE_TOKENS. What the gate does -- catch a token in
#   a tree, in an untracked file, in history, in an empty commit's message;
#   not fail open; report every match -- is a property of the tool, not of
#   which names are in the list, so invented names test it exactly as well and
#   leave nothing behind here. They also make these tests run identically on a
#   machine that has no overlay at all.
#
#   Properties OF THE REAL LIST -- that it cannot match the OS username, and
#   that no file shipped in this repo contains one of its entries -- are
#   checked against whatever list the gate actually resolves, and SKIP when
#   there is none. The real names are read at runtime from the private
#   overlay; they are never written down to be asserted against.
#
# The invented names below are chosen to appear nowhere in this repository, so
# a fixture can never be confused with real content.
FAKE_COMPANY='acmerobotics'
FAKE_MONO='acme-ros-mono'
FAKE_STAGE='acme-stage'
FAKE_NAV='acme_nav'
FAKE_WG='AcmeVPN'
FAKE_KEY='ACME-4268'
FAKE_AGENT='builder-amd-agent-2'
FAKE_PARTNER='fablift'
FAKE_HOST='ci.internal.example'

# Written as a token file, in the same shape a real overlay supplies: one
# extended-regex fragment per line, with the dots escaped and the issue key
# anchored to a following digit.
_fake_tokens() {
  cat > "$1" <<'TOKENS'
# invented -- see the header of this file
acmerobotics
acme-ros-mono
acme-stage
acme_nav
AcmeVPN
ACME-[0-9]
builder-amd-agent
ci\.internal\.example
fablift
TOKENS
}

# The gate, run against a known list. Every behaviour test goes through this,
# so none of them depends on what the machine happens to have installed.
_gate() {
  local tokens="$1"; shift
  SCRUB_GATE_TOKENS="$tokens" "$REPO_ROOT/bin/scrub-gate" "$@"
}

# The list the gate resolves on THIS machine, or empty if it resolves none.
# Read from the tool rather than from a file path guessed here, so the tests
# follow the tool's own resolution order wherever it points.
_effective_tokens() { "$REPO_ROOT/bin/scrub-gate" --print-tokens 2>/dev/null || true; }

_scrub_fixture() {
  local dir="$1" content="$2"
  mkdir -p "$dir"
  ( cd "$dir" && git init -q . && printf '%s\n' "$content" > f.txt \
    && git add f.txt && git -c user.email=t@t -c user.name=t commit -qm x )
}

# --- The list is data, and it is not in this repository ---------------------

test_repo_ships_an_example_list_and_no_live_one() {
  # The two halves of the round-5 change, as an enforced property rather than
  # a claim: there is a documented example, and there is no file anywhere in
  # the tracked tree that the gate would pick up as a real source. A live list
  # committed here by accident -- at bin/, or under a vendored overlay -- would
  # put the names straight back into the public history it was moved out of.
  local what="the repo ships an example token list and no live one"

  if [[ ! -f "$REPO_ROOT/bin/scrub-tokens.example" ]]; then
    fail "$what" "bin/scrub-tokens.example is missing"
    return
  fi

  local live
  live="$(git -C "$REPO_ROOT" ls-files -- '*scrub-gate/tokens' '*scrub-gate/tokens.d/*' \
            '.config/scrub-gate/*' 2>/dev/null)" || true
  if [[ -z "$live" ]]; then
    pass "$what"
  else
    fail "$what" "a live token list is tracked here: $(printf '%s' "$live" | tr '\n' ' ')"
  fi
}

test_gate_refuses_a_verdict_when_it_has_no_list() {
  # The failure this replaces is the whole reason the list moved out: a gate
  # that finds nothing because it was handed nothing must not look like a gate
  # that looked and found nothing. The fixture is DIRTY -- it holds a token
  # that any sane list would catch -- so a 0 here would be a false all-clear on
  # real employer content, not merely an empty run.
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _scrub_fixture "$tmp/r" "builds run on $FAKE_MONO nightly"
  mkdir -p "$tmp/no-dir" "$tmp/no-overlays"

  local what="gate refuses a verdict with no token list"
  local out status
  out="$(SCRUB_GATE_TOKENS_DIR="$tmp/no-dir" SCRUB_GATE_OVERLAYS="$tmp/no-overlays" \
         "$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -eq 3 ]]; then
    pass "$what (exit 3, not 0)"
  else
    fail "$what (exit 3, not 0)" "exit $status on a dirty repo with no list"
  fi
  assert_contains "$out" "NO VERDICT" "gate says it reached no verdict"
  assert_contains "$out" "not a clean result" "gate spells out that this is not clean"

  # --print-tokens must not quietly print an empty list either: a caller that
  # greps with "" matches every line of everything.
  # `|| true` must NOT appear here: it would make $? the status of `true`, and
  # this assertion would pass whatever the gate did. The harness does not set
  # -e, so a non-zero assignment is safe to leave unguarded.
  local printed pstatus
  printed="$(SCRUB_GATE_TOKENS_DIR="$tmp/no-dir" SCRUB_GATE_OVERLAYS="$tmp/no-overlays" \
             "$REPO_ROOT/bin/scrub-gate" --print-tokens 2>/dev/null)"
  pstatus=$?
  if [[ -z "$printed" && "$pstatus" -ne 0 ]]; then
    pass "$what (--print-tokens also refuses)"
  else
    fail "$what (--print-tokens also refuses)" "printed [$printed] exit $pstatus"
  fi
}

test_gate_rejects_an_explicit_list_that_is_not_there() {
  # A typo in $SCRUB_GATE_TOKENS must be an error, not a silent fall-through
  # to the machine's other sources -- otherwise a run you believe is using one
  # list is quietly using another.
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _scrub_fixture "$tmp/r" "clean"

  local what="gate rejects an explicit token file that does not exist"
  local out status
  out="$(SCRUB_GATE_TOKENS="$tmp/absent" "$REPO_ROOT/bin/scrub-gate" "$tmp/r" 2>&1)"
  status=$?
  if [[ "$status" -eq 2 ]]; then
    pass "$what (exit 2)"
  else
    fail "$what (exit 2)" "exit $status"
  fi
  assert_contains "$out" "SCRUB_GATE_TOKENS" "gate names the variable it could not resolve"
}

test_gate_unions_every_overlay_list_it_finds() {
  # The reason the list is a file rather than a constant: a second overlay, for
  # a different employer, contributes its own names with no change to this
  # repo. Both lists must be in force at once, not the first one found.
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  mkdir -p "$tmp/ov/one/scrub-gate" "$tmp/ov/two/scrub-gate" "$tmp/no-dir"
  printf '# a comment\n\nfirstname  \n' > "$tmp/ov/one/scrub-gate/tokens"
  printf 'secondname\n' > "$tmp/ov/two/scrub-gate/tokens"

  local what="gate unions the lists from every overlay"
  local tokens
  tokens="$(SCRUB_GATE_TOKENS_DIR="$tmp/no-dir" SCRUB_GATE_OVERLAYS="$tmp/ov" \
            "$REPO_ROOT/bin/scrub-gate" --print-tokens)" || true
  assert_eq "firstname|secondname" "$tokens" "$what (comments, blanks and padding dropped)"

  _scrub_fixture "$tmp/r" "this mentions secondname once"
  local status
  SCRUB_GATE_TOKENS_DIR="$tmp/no-dir" SCRUB_GATE_OVERLAYS="$tmp/ov" \
    "$REPO_ROOT/bin/scrub-gate" "$tmp/r" >/dev/null 2>&1
  status=$?
  if [[ "$status" -eq 1 ]]; then
    pass "$what (the second overlay's token is in force)"
  else
    fail "$what (the second overlay's token is in force)" "exit $status"
  fi
}

# --- Behaviour, against an invented list ------------------------------------

test_gate_catches_employer_token_in_tree() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _fake_tokens "$tmp/tokens"
  _scrub_fixture "$tmp/r" "builds run on $FAKE_MONO nightly"

  local out status
  out="$(_gate "$tmp/tokens" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches a monorepo name in the tree (exit status)"
  else
    fail "gate catches a monorepo name in the tree (exit status)" "gate passed a listed token"
  fi
  assert_contains "$out" "employer tokens" "gate names the tree finding"
  assert_contains "$out" "$FAKE_MONO" "gate reports the matched token (tree)"
}

test_gate_catches_employer_token_only_in_history() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _fake_tokens "$tmp/tokens"
  _scrub_fixture "$tmp/r" "reachable on $FAKE_WG only"
  ( cd "$tmp/r" && printf 'clean\n' > f.txt \
    && git add f.txt && git -c user.email=t@t -c user.name=t commit -qm scrub )

  local out status
  out="$(_gate "$tmp/tokens" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches a token only present in history (exit status)"
  else
    fail "gate catches a token only present in history (exit status)" "clean tip hid a dirty history"
  fi
  assert_contains "$out" "employer tokens" "gate names the history finding"
  assert_contains "$out" "$FAKE_WG" "gate reports the matched token (history)"
}

test_gate_catches_employer_token_in_untracked_file() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _fake_tokens "$tmp/tokens"
  _scrub_fixture "$tmp/r" "clean tracked content"
  printf 'staging deploys go through %s\n' "$FAKE_STAGE" > "$tmp/r/untracked.txt"

  local out status
  out="$(_gate "$tmp/tokens" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches an employer token in an untracked file (exit status)"
  else
    fail "gate catches an employer token in an untracked file (exit status)" "untracked file with a token passed the gate"
  fi
  assert_contains "$out" "employer tokens" "gate names the untracked finding"
  assert_contains "$out" "$FAKE_STAGE" "gate reports the matched token (untracked)"
}

test_gate_ignores_a_name_that_is_not_on_the_list() {
  # The other half of the OS-username property, in a form that needs no real
  # name: content that merely resembles a token -- shares a prefix with one --
  # must not be reported. `acme_vhr` is to `acme_nav` what the real username is
  # to the real ROS package names.
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _fake_tokens "$tmp/tokens"
  _scrub_fixture "$tmp/r" "config lives in /home/acme_vhr/.config and id acme_vhr.battery"

  if _gate "$tmp/tokens" "$tmp/r" >/dev/null 2>&1; then
    pass "gate ignores a lookalike that is not a listed token"
  else
    fail "gate ignores a lookalike that is not a listed token" "false positive on a prefix match"
  fi
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
  for i in $(seq 1 12); do line+="builds run on $FAKE_MONO nightly "; done
  mkdir -p "$dir"
  (
    cd "$dir" && git init -q .
    for i in $(seq 1 400); do printf '%s %s\n' "$line" "$i" > "f$i.txt"; done
    git add -A && git -c user.email=t@t -c user.name=t commit -qm bulk
  ) >/dev/null
}

test_gate_does_not_fail_open_on_a_many_match_tree() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _fake_tokens "$tmp/tokens"
  _scrub_big_fixture "$tmp/r"

  local what="gate does not fail open on a tree with many matches"
  local out status
  out="$(_gate "$tmp/tokens" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "$what (exit status)"
  else
    fail "$what (exit status)" "400 matching files and the gate reported clean"
  fi

  # Not just "it noticed something": every match has to survive to the report,
  # which is the part SIGPIPE truncated.
  local reported want
  reported="$(printf '%s\n' "$out" | grep -c -- "$FAKE_MONO" || true)"
  want=400
  if [[ "$reported" -ge "$want" ]]; then
    pass "$what (all $want matches reported)"
  else
    fail "$what (all $want matches reported)" "reported $reported of $want"
  fi
}

test_gate_does_not_fail_open_on_a_many_match_history() {
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _fake_tokens "$tmp/tokens"
  _scrub_big_fixture "$tmp/r"
  # Scrub the tree so only the history is dirty -- and leave the history large,
  # so the `git log -p --all | grep | grep -q .` chain has the same race.
  ( cd "$tmp/r" && git rm -q -r . >/dev/null && printf 'clean\n' > ok.txt \
    && git add ok.txt && git -c user.email=t@t -c user.name=t commit -qm scrub ) >/dev/null

  local what="gate does not fail open on a large dirty history"
  local out status
  out="$(_gate "$tmp/tokens" "$tmp/r" 2>&1)"
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
  # so this keeps working now that the repo is genuinely scrubbed.
  #
  # This one uses the EFFECTIVE list, because its whole point is to check the
  # tool against the real repository it will be run on.
  local what="gate verdict agrees with a direct capture on this repo"
  local tokens
  tokens="$(_effective_tokens)"
  if [[ -z "$tokens" ]]; then
    pass "$what (skipped: no token list on this machine)"
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

# --- Properties of the REAL list, read at runtime ---------------------------

test_effective_token_list_cannot_match_the_os_username() {
  # The one property that cannot be tested with invented names, because it is
  # a property of this machine: no fragment may match the login name or $HOME.
  # A list that did would report every absolute path in every repository, bury
  # the real findings, and get the gate turned off.
  #
  # Derived from `id -un` rather than from a username written down here, so it
  # keeps working -- and keeps meaning something -- on any machine and for any
  # overlay's list.
  local what="the effective token list cannot match the OS username or \$HOME"
  local tokens
  tokens="$(_effective_tokens)"
  if [[ -z "$tokens" ]]; then
    pass "$what (skipped: no token list on this machine)"
    return
  fi

  local user; user="$(id -un)"
  local probe="/home/$user/.config/app $user.plugin.id $HOME/bin"
  local bad="" t
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    if printf '%s\n' "$probe" | grep -qiE -- "$t" 2>/dev/null; then
      bad+="[$t] "
    fi
  done < <(printf '%s\n' "$tokens" | tr '|' '\n')

  if [[ -z "$bad" ]]; then
    pass "$what"
  else
    fail "$what" "these match the username or a home path: $bad"
  fi
}

test_no_file_in_this_repo_holds_a_real_token() {
  # The invariant that lets the gate scan with no exclusions at all, now
  # stated over the WHOLE tracked tree rather than just bin/ and tests/.
  # Round 4 checked two directories because those were the two the list lived
  # in; the list lives nowhere here any more, so the honest check is
  # everything -- which is exactly what `scrub-gate "$REPO_ROOT"` already does
  # for the tree, the untracked files and the history. This adds the part that
  # is specifically about the tool's own shipped files being clean, with the
  # line numbers, so a reintroduction is named rather than merely counted.
  local what="no file shipped in this repo holds a real employer token"
  local tokens
  tokens="$(_effective_tokens)"
  if [[ -z "$tokens" ]]; then
    pass "$what (skipped: no token list on this machine)"
    return
  fi

  local hits
  hits="$(grep -rnIiE -- "$tokens" "$REPO_ROOT/bin" "$REPO_ROOT/tests" 2>/dev/null)" || true
  if [[ -z "$hits" ]]; then
    pass "$what (bin/ and tests/)"
  else
    fail "$what (bin/ and tests/)" "$(printf '%s' "$hits" | head -3 | tr '\n' ' ')"
  fi

  local tracked
  tracked="$(git -C "$REPO_ROOT" grep -IinE -- "$tokens" -- . 2>/dev/null)" || true
  if [[ -z "$tracked" ]]; then
    pass "$what (whole tracked tree)"
  else
    fail "$what (whole tracked tree)" "$(printf '%s' "$tracked" | head -3 | tr '\n' ' ')"
  fi
}

# --- Fix round 4 (Task 12): the gate must have no blind spot at all ---------
#
# Fix round 3 excluded bin/scrub-gate and tests/test_scrub_gate.sh by pathspec
# so the gate would stop matching its own token list. Two holes followed, both
# reproduced before that round: a real token at either of those paths, in ANY
# repo the gate is pointed at, returned exit 0; and the pathspec on the history
# scan silently dropped every empty commit's message, because a commit that
# touches no path survives no path filter.
#
# Both exclusions are gone, and what made them unnecessary is now upstream of
# the repository as well as of the scan: there is no list here to match.

test_gate_catches_a_real_token_at_its_own_two_paths() {
  # The property fix round 3 claimed in a test name and never checked. A repo
  # whose ONLY employer content sits at bin/scrub-gate and
  # tests/test_scrub_gate.sh must still be refused, and each planted token must
  # be named in the report -- no third file to carry the verdict this time.
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _fake_tokens "$tmp/tokens"
  mkdir -p "$tmp/r/bin" "$tmp/r/tests"
  printf 'deploy target is %s\n' "$FAKE_HOST" > "$tmp/r/bin/scrub-gate"
  printf 'owned by %s\n' "$FAKE_COMPANY" > "$tmp/r/tests/test_scrub_gate.sh"
  ( cd "$tmp/r" && git init -q . \
      && git add -A && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null

  local out status
  out="$(_gate "$tmp/tokens" "$tmp/r" 2>&1)"
  status=$?

  local what="gate catches a real token at bin/scrub-gate and tests/test_scrub_gate.sh"
  if [[ "$status" -ne 0 ]]; then
    pass "$what (exit status)"
  else
    fail "$what (exit status)" "a repo whose only employer content is at those two paths passed the gate"
  fi
  assert_contains "$out" "bin/scrub-gate" "gate names the hit at bin/scrub-gate"
  assert_contains "$out" "$FAKE_HOST" "gate reports the token planted at bin/scrub-gate"
  assert_contains "$out" "tests/test_scrub_gate.sh" "gate names the hit at tests/test_scrub_gate.sh"
  assert_contains "$out" "$FAKE_COMPANY" "gate reports the token planted at tests/test_scrub_gate.sh"

  # Untracked, at the same two paths: the pathspec hid those too.
  local tmp2; tmp2="$(mktemp -d)"
  mkdir -p "$tmp2/r/bin"
  ( cd "$tmp2/r" && git init -q . && printf 'clean\n' > ok.txt && git add ok.txt \
      && git -c user.email=t@t -c user.name=t commit -qm x ) >/dev/null
  printf 'deploy target is %s\n' "$FAKE_HOST" > "$tmp2/r/bin/scrub-gate"
  if _gate "$tmp/tokens" "$tmp2/r" >/dev/null 2>&1; then
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
  _fake_tokens "$tmp/tokens"
  mkdir -p "$tmp/r"
  (
    cd "$tmp/r" && git init -q .
    printf 'clean\n' > ok.txt && git add ok.txt
    git -c user.email=t@t -c user.name=t commit -qm seed
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m "rollout to $FAKE_HOST"
  ) >/dev/null

  local out status
  out="$(_gate "$tmp/tokens" "$tmp/r" 2>&1)"
  status=$?

  local what="gate catches a token in an empty commit's message"
  if [[ "$status" -ne 0 ]]; then
    pass "$what (exit status)"
  else
    fail "$what (exit status)" "an empty commit carrying the token in its message passed the gate"
  fi
  assert_contains "$out" "employer tokens in history" "gate names the history finding (message)"
  assert_contains "$out" "$FAKE_HOST" "gate reports the token from the commit message"

  # A commit whose only change is at one of the two formerly-excluded paths:
  # dropped by the pathspec, message and diff together.
  local tmp2; tmp2="$(mktemp -d)"
  mkdir -p "$tmp2/r/bin"
  (
    cd "$tmp2/r" && git init -q .
    printf 'clean\n' > ok.txt && git add ok.txt
    git -c user.email=t@t -c user.name=t commit -qm seed
    printf 'x\n' > bin/scrub-gate && git add bin/scrub-gate
    git -c user.email=t@t -c user.name=t commit -qm "point it at $FAKE_WG"
    git rm -q bin/scrub-gate
    git -c user.email=t@t -c user.name=t commit -qm cleanup
  ) >/dev/null
  local out2
  out2="$(_gate "$tmp/tokens" "$tmp2/r" 2>&1)" || true
  if [[ "$out2" == *"$FAKE_WG"* ]]; then
    pass "gate catches a message on a commit that touches only bin/scrub-gate"
  else
    fail "gate catches a message on a commit that touches only bin/scrub-gate" \
      "the commit's message never reached the scan"
  fi
  rm -rf "$tmp2"
}

test_gate_catches_several_listed_tokens_at_once() {
  # Was test_gate_catches_a_newly_added_token: the fix-round-2 widening added a
  # ROS package name, a second issue-key prefix, a partner brand and a build
  # agent, all of which the narrow list had passed. What that test really pins
  # is that every fragment in a list is in force, not just the first -- which
  # matters more now that a list can be assembled from several overlay files.
  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  _fake_tokens "$tmp/tokens"
  _scrub_fixture "$tmp/r" \
    "the ros package $FAKE_NAV and issue $FAKE_KEY on $FAKE_AGENT with a $FAKE_PARTNER lift"

  local out status
  out="$(_gate "$tmp/tokens" "$tmp/r" 2>&1)"
  status=$?

  if [[ "$status" -ne 0 ]]; then
    pass "gate catches tokens from the middle and end of the list (exit status)"
  else
    fail "gate catches tokens from the middle and end of the list (exit status)" "listed tokens still passed the gate"
  fi
  local t
  for t in "$FAKE_NAV" "$FAKE_KEY" "$FAKE_AGENT" "$FAKE_PARTNER"; do
    assert_contains "$out" "$t" "gate reports the matched token ($t)"
  done
}
