#!/usr/bin/env bash
# Phase A capture-and-split checks. Later tasks append their own test_*
# functions here as they move, split and rewrite these repos.

# --- The private overlay, discovered rather than named ----------------------
#
# The work-specific half of this configuration lives in a separate, private
# overlay repository. WHOSE it is is not this repository's business, and until
# Task 11 fix round 1 these tests said so out loud: the overlay's directory
# name, and both private repository names, were written down here in a public
# file. They are read at runtime now -- the directory by looking for the one
# that carries an overlay.toml, the repository names from that file -- so the
# same tests work for any overlay and name none of them.
#
# Exactly one overlay is expected. Two is ambiguous, and guessing which one a
# test meant is worse than saying so.
_overlay_dir() {
  local root="${OMARCHY_OVERLAYS:-$HOME/omarchy_configuration/overlays}" d found=""
  [[ -d "$root" ]] || return 1
  for d in "$root"/*/; do
    [[ -f "$d/overlay.toml" ]] || continue
    [[ -n "$found" ]] && return 2
    found="${d%/}"
  done
  [[ -n "$found" ]] || return 1
  printf '%s\n' "$found"
}

# One quoted scalar out of the overlay's overlay.toml: _overlay_meta repo
_overlay_meta() {
  local o; o="$(_overlay_dir)" || return 1
  local v
  v="$(sed -nE "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*\"(.*)\"[[:space:]]*\$/\\1/p" \
        "$o/overlay.toml" 2>/dev/null | head -1)"
  [[ -n "$v" ]] || return 1
  printf '%s\n' "$v"
}

# The token list the gate resolves on this machine, or empty. Tests that need
# it SKIP when it is absent: since fix round 1 the list is supplied by the
# overlay, so a public-only checkout legitimately has none, and reporting that
# as a failure would train people to ignore a red suite.
_effective_tokens() { "$REPO_ROOT/bin/scrub-gate" --print-tokens 2>/dev/null || true; }

test_no_untracked_config_in_base_repo() {
  # There are two ways a captured file silently fails to reach a clone, and
  # only one of them shows up in a plain `git status`:
  #   1. never `git add`ed           -> listed as `??`
  #   2. matched by some .gitignore  -> listed as nothing at all, without --ignored
  # (2) is how dotfiles/omarchy/themes/aetheria/README.md went missing: the
  # captured theme brought its upstream .gitignore (`*.md`, `.git/`) along with
  # its content, and that vendored file then governed this repo. A
  # captured-but-ignored file is exactly the "lives only on this disk" failure
  # this phase exists to end, so it has to fail the same as an untracked one.
  #
  # The timestamped backups omarchy and the install scripts leave behind *are*
  # ignored on purpose, by this repo's own root .gitignore. `git check-ignore
  # -v` names the file that supplied the rule, so this accepts the repo root's
  # own rules and rejects any .gitignore that arrived as captured content.
  local dirs=(dotfiles/ home/ bin-local/ manifests/)
  local what="no untracked or silently ignored files under captured config"
  local problems="" p src

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    problems+="untracked: $p; "
  done < <(git -C "$REPO_ROOT" status --porcelain -- "${dirs[@]}" | sed -n 's/^?? //p')

  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    src="$(git -C "$REPO_ROOT" check-ignore -v -- "$p" 2>/dev/null | cut -f1)"
    [[ "$src" == .gitignore:* ]] && continue
    problems+="ignored by ${src:-<unknown>}: $p; "
  done < <(git -C "$REPO_ROOT" status --porcelain --ignored -- "${dirs[@]}" | sed -n 's/^!! //p')

  if [[ -z "$problems" ]]; then
    pass "$what"
  else
    fail "$what" "$problems"
  fi
}

test_hyprland_requires_resolve_in_repo() {
  # Parses the live require("hypr.X") graph out of the captured hyprland.lua,
  # rather than pinning today's known-good module list, so a future
  # require("hypr.something") with no matching file gets caught even if
  # nobody remembers to update this test.
  local f="$REPO_ROOT/dotfiles/hypr/hyprland.lua"
  local what="hyprland.lua requires resolve to tracked files"

  if [[ ! -f "$f" ]]; then
    fail "$what" "hyprland.lua not found at $f"
    return
  fi

  local missing="" mod
  while IFS= read -r mod; do
    [[ -n "$mod" ]] || continue
    [[ -f "$REPO_ROOT/dotfiles/hypr/$mod.lua" ]] || missing+="$mod "
  done < <(grep -oE 'require\("hypr\.[A-Za-z0-9_]+"\)' "$f" \
            | sed -E 's/require\("hypr\.([A-Za-z0-9_]+)"\)/\1/')

  if [[ -z "$missing" ]]; then
    pass "$what"
  else
    fail "$what" "missing: $missing"
  fi
}

test_work_overlay_matches_contract() {
  # Checks what a clone would actually receive, not local disk: git tracks
  # no empty directory, so a bare `mkdir -p` for a contract directory
  # survives on this machine but vanishes from a clone of the pushed repo.
  # `git ls-tree -r HEAD` is the tracked-tree truth; each contract directory
  # must have at least one tracked path under it (a .gitkeep, if nothing
  # else) to count as present. Network-free: reads the local overlay repo
  # only, never clones.
  local what="work overlay matches the contract shape"
  local o
  if ! o="$(_overlay_dir)"; then
    fail "$what" "no single overlay found under ${OMARCHY_OVERLAYS:-$HOME/omarchy_configuration/overlays}"
    return
  fi

  if [[ ! -d "$o/.git" ]]; then
    fail "$what" "overlay at $o is not a git repository"
    return
  fi

  local tree
  tree="$(git -C "$o" ls-tree -r HEAD --name-only 2>&1)" || {
    fail "$what" "git ls-tree failed: $tree"
    return
  }

  local missing="" p
  grep -qxF "overlay.toml" <<<"$tree" || missing+="overlay.toml "
  # scrub-gate/ joined the contract in Task 11 fix round 1: the token list the
  # public gate runs on is supplied from here, so an overlay without one leaves
  # the gate unable to reach a verdict at all.
  for p in dotfiles home bashrc.d manifests manifests/desktop nvim install-scripts scrub-gate; do
    grep -q "^${p}/" <<<"$tree" || missing+="$p "
  done

  if [[ -z "$missing" ]]; then
    pass "$what"
  else
    fail "$what" "missing from tracked tree: $missing"
  fi
}

test_every_audited_homeless_file_is_captured() {
  local missing=""
  local want=(
    dotfiles/hypr/hyprland.lua dotfiles/hypr/monitors.lua
    dotfiles/hypr/input.lua dotfiles/hypr/looknfeel.lua
    dotfiles/hypr/hyprlock.conf dotfiles/hypr/hypridle.conf
    dotfiles/hypr/hyprsunset.conf dotfiles/hypr/xdph.conf
    dotfiles/omarchy/shell.json
    dotfiles/omarchy/extensions/omarchy-menu.jsonc
    dotfiles/mise/config.toml dotfiles/git/config
    dotfiles/systemd/user/ssh-agent.service
    dotfiles/systemd/user/voxtype.service
    dotfiles/systemd/user/omarchy-logitech.service
    dotfiles/systemd/user/omarchy-logitech.service.d/10-system-python.conf
    dotfiles/hyprland-preview-share-picker/config.yaml
    home/.XCompose home/.bash_profile home/.profile home/.zshrc
    bin-local/logi bin-local/herdr-focus-pane
  )
  for f in "${want[@]}"; do
    [[ -e "$REPO_ROOT/$f" ]] || missing+="$f "
  done
  if [[ -z "$missing" ]]; then
    pass "all audited homeless files are captured"
  else
    fail "all audited homeless files are captured" "missing: $missing"
  fi
}

test_xcompose_carries_no_employer_address() {
  # The address is never written down here. Until this fix round it was: the
  # failure message below held a literal work address, so the test that exists
  # to keep employer addresses out of the public tree was itself putting one
  # there. The pattern now comes from bin/scrub-gate's own TOKENS list, which
  # also widens the check from one address to every employer token. It is read
# via `bin/scrub-gate --print-tokens`, not sed'd out of the source: the gate
# now assembles its tokens from halves so its own file holds none as a
# literal, and there is no TOKENS='...' line left to scrape.
  local f="$REPO_ROOT/home/.XCompose"
  local what="base .XCompose has no employer address"

  # A missing file used to pass vacuously: `grep -q ... nonexistent` is
  # non-zero, which took the else branch.
  if [[ ! -f "$f" ]]; then
    fail "$what" "home/.XCompose is missing -- nothing was checked"
    return
  fi

  local tokens
  tokens="$(_effective_tokens)"
  if [[ -z "$tokens" ]]; then
    pass "$what (skipped: no token list on this machine)"
    return
  fi

  local hits
  hits="$(grep -inE "$tokens" "$f")" || true
  if [[ -z "$hits" ]]; then
    pass "$what"
  else
    fail "$what" \
      "an employer token from bin/scrub-gate's list is still in the base copy, line(s): $(printf '%s' "$hits" | cut -d: -f1 | tr '\n' ' ')"
  fi
}

test_work_overlay_is_private() {
  # "Cannot check" (network down, or gh unauthenticated) must never be
  # conflated with "check failed" (the earlier bug this replicates: b9adac3
  # fixed the same shape for the backup test). Each cause is probed on its
  # own evidence, in order, so a later step's failure can only mean what it
  # claims to mean:
  #   1. GitHub API reachability - a public, unauthenticated endpoint, so a
  #      failure here is unambiguously network-down, not auth or the repo.
  #   2. gh auth status - checked only once reachability is confirmed, so a
  #      failure here is unambiguously "not logged in", not network.
  #   3. The actual repo query - reachable and authenticated, so a missing
  #      repo or wrong visibility here is a real finding, not a skip.
  local what="work overlay repo is private"
  local repo
  if ! repo="$(_overlay_meta repo)"; then
    pass "$what (skipped: no overlay, or it declares no repo)"
    return
  fi

  if ! timeout 8 gh api /zen >/dev/null 2>&1; then
    pass "$what (skipped: GitHub API unreachable)"
    return
  fi

  if ! timeout 8 gh auth status >/dev/null 2>&1; then
    pass "$what (skipped: gh not authenticated)"
    return
  fi

  local vis rc
  vis="$(timeout 8 gh repo view "$repo" --json visibility --jq .visibility 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    fail "$what" "gh repo view failed (exit $rc): $vis"
    return
  fi
  assert_eq "PRIVATE" "$vis" "$what"
}

# --- Fix round 1: splits that actually reassemble ---------------------------
#
# Three files are split between this public repo and the private work overlay.
# shell.json was the only one that was ever put back together again: the other
# two had a scrubbed base copy and an orphan overlay fragment with nothing
# wiring them to each other. These pin all of it.

test_git_config_split_reassembles_with_the_overlay() {
  # base dotfiles/git/config + the overlay's ~/.gitconfig.d fragment must
  # produce the same user.email the live ~/.config/git/config has.
  #
  # The include is absolute (tilde) on purpose: git resolves a relative
  # include.path against the *including file's* directory, which is
  # ~/.config/git/ -- inside the base repo's stow target, where no overlay
  # fragment can ever be.
  local what="git config split reassembles with the overlay"
  local base="$REPO_ROOT/dotfiles/git/config"
  local frag; frag="$(_overlay_dir)/home/.gitconfig.d/work-email"
  local live="$HOME/.config/git/config"

  local f
  for f in "$base" "$frag" "$live"; do
    if [[ ! -f "$f" ]]; then
      fail "$what" "missing: $f"
      return
    fi
  done

  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  mkdir -p "$tmp/home/.gitconfig.d"
  cp "$frag" "$tmp/home/.gitconfig.d/work-email"

  local want got
  want="$(git config -f "$live" --get user.email 2>/dev/null)" || true
  got="$(HOME="$tmp/home" git config -f "$base" --includes --get user.email 2>/dev/null)" || true

  if [[ -n "$want" && "$want" == "$got" ]]; then
    pass "$what"
  else
    fail "$what" "reassembled user.email does not match the live one (live set: $([[ -n "$want" ]] && echo yes || echo no), reassembled set: $([[ -n "$got" ]] && echo yes || echo no))"
  fi

  # And the base alone has to be a usable git config: no employer identity of
  # its own, and no error from the dangling include.
  local rc leaked
  HOME="$tmp/nohome" git config -f "$base" --includes --list >/dev/null 2>&1
  rc=$?
  leaked="$(HOME="$tmp/nohome" git config -f "$base" --includes --get user.email 2>/dev/null)" || true
  if [[ $rc -eq 0 && -z "$leaked" ]]; then
    pass "base git config is clean and parses with no overlay applied"
  else
    fail "base git config is clean and parses with no overlay applied" \
      "git config exit $rc, user.email set: $([[ -n "$leaked" ]] && echo yes || echo no)"
  fi
}

test_xcompose_split_reassembles_with_the_overlay() {
  # bin/assemble-xcompose is the .XCompose equivalent of `jq -f shell.json.jq`.
  # Assembled base + overlay fragment must compile to the same compose table as
  # the live ~/.XCompose.
  local what="XCompose split reassembles with the overlay"
  local base="$REPO_ROOT/home/.XCompose"
  local fragdir; fragdir="$(_overlay_dir)/home/.XCompose.d"
  local live="$HOME/.XCompose"
  local assemble="$REPO_ROOT/bin/assemble-xcompose"

  local f
  for f in "$base" "$live" "$assemble"; do
    if [[ ! -e "$f" ]]; then
      fail "$what" "missing: $f"
      return
    fi
  done
  if [[ ! -d "$fragdir" ]]; then
    fail "$what" "overlay fragment directory missing: $fragdir"
    return
  fi

  if ! command -v xkbcli >/dev/null 2>&1; then
    pass "$what (skipped: xkbcli not installed, cannot compile a compose table)"
    return
  fi

  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  "$assemble" "$base" "$fragdir" > "$tmp/assembled" 2>/dev/null

  local got want
  got="$(xkbcli compile-compose "$tmp/assembled" 2>/dev/null | sort)"
  want="$(xkbcli compile-compose "$live" 2>/dev/null | sort)"
  if [[ -n "$want" && "$got" == "$want" ]]; then
    pass "$what"
  else
    fail "$what" "assembled table differs from the live ~/.XCompose"
  fi

  # The reason the include is generated rather than written into the base file:
  # libxkbcommon aborts the whole table on a missing include, so a hardcoded
  # one would cost a base-only machine every sequence it has.
  local rc
  xkbcli compile-compose --test "$base" >/dev/null 2>&1
  rc=$?
  if [[ $rc -eq 0 ]]; then
    pass "base .XCompose still compiles with no overlay applied"
  else
    fail "base .XCompose still compiles with no overlay applied" "xkbcli exit $rc"
  fi
}

test_base_keybindings_carry_no_employer_content() {
  # Pattern comes from bin/scrub-gate's TOKENS so no employer string is
  # written down here.
  local what="base hypr keybindings and autostart are employer-free"
  local tokens
  tokens="$(_effective_tokens)"
  if [[ -z "$tokens" ]]; then
    pass "$what (skipped: no token list on this machine)"
    return
  fi

  local hits f
  hits=""
  for f in dotfiles/hypr/bindings.lua dotfiles/hypr/autostart.lua; do
    if [[ ! -f "$REPO_ROOT/$f" ]]; then
      fail "$what" "missing: $f"
      return
    fi
    local n
    n="$(grep -icE "$tokens" "$REPO_ROOT/$f")" || true
    [[ "$n" -gt 0 ]] && hits+="$f:$n "
  done

  if [[ -z "$hits" ]]; then
    pass "$what"
  else
    fail "$what" "employer tokens still present, file:count -- $hits"
  fi
}

test_overlay_keybinding_fragment_is_loaded_by_the_base_bindings() {
  # The keybindings split is only real if a machine with the overlay applied
  # still gets the binds. This runs the actual base bindings.lua under a
  # stubbed Hyprland Lua API -- once with the overlay's bindings.d fragment
  # present, once without -- and compares what got bound.
  #
  # The expected key list is produced by running the overlay fragment through
  # the same stub rather than being written out here, so the public repo never
  # has to name a work app.
  local what="overlay bindings.d fragment reaches the base bindings.lua"
  local bindings="$REPO_ROOT/dotfiles/hypr/bindings.lua"

  if ! command -v lua >/dev/null 2>&1; then
    pass "$what (skipped: lua not installed)"
    return
  fi
  if [[ ! -f "$bindings" ]]; then
    fail "$what" "missing: $bindings"
    return
  fi

  # Every fragment the overlay ships, found by glob rather than by name -- the
  # fragment used to be named here, which put the overlay's name in a public
  # file for no benefit.
  local o frags=()
  if ! o="$(_overlay_dir)"; then
    pass "$what (skipped: no overlay on this machine)"
    return
  fi
  local g
  for g in "$o"/dotfiles/hypr/bindings.d/*.lua; do
    [[ -f "$g" ]] && frags+=("$g")
  done
  if [[ ${#frags[@]} -eq 0 ]]; then
    fail "$what" "the overlay ships no dotfiles/hypr/bindings.d/*.lua fragment"
    return
  fi

  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  mkdir -p "$tmp/cfg/hypr/bindings.d" "$tmp/empty/hypr"
  cp "${frags[@]}" "$tmp/cfg/hypr/bindings.d/"

  cat > "$tmp/harness.lua" <<'LUA'
local bound = {}
local function noop() end
local function maker() return noop end
hl = {
  unbind = noop,
  dsp = {
    focus = maker(), layout = maker(),
    window = { close = maker(), resize = maker(), swap = maker() },
    workspace = { move = maker(), toggle_special = maker() },
  },
}
o = {
  bind = function(key) bound[#bound + 1] = key end,
  launch_on_start = noop,
  exec_on_start = noop,
  launch_webapp = maker(),
}
dofile(os.getenv("BINDINGS"))
for _, key in ipairs(bound) do print(key) end
LUA

  local want="" with without f2
  for f2 in "${frags[@]}"; do
    want+="$(BINDINGS="$f2" lua "$tmp/harness.lua" 2>/dev/null)"$'\n'
  done
  want="$(printf '%s' "$want" | sort -u | sed '/^$/d')"
  if [[ -z "$want" ]]; then
    fail "$what" "the overlay fragments bound nothing -- harness or fragment is broken"
    return
  fi
  with="$(XDG_CONFIG_HOME="$tmp/cfg" BINDINGS="$bindings" lua "$tmp/harness.lua" 2>/dev/null | sort -u)"
  without="$(XDG_CONFIG_HOME="$tmp/empty" BINDINGS="$bindings" lua "$tmp/harness.lua" 2>/dev/null | sort -u)"

  local missing="" leaked="" k
  while IFS= read -r k; do
    [[ -n "$k" ]] || continue
    grep -qxF "$k" <<<"$with" || missing+="[$k] "
    grep -qxF "$k" <<<"$without" && leaked+="[$k] "
  done <<<"$want"

  if [[ -z "$missing" ]]; then
    pass "$what (binds arrive with the overlay applied)"
  else
    fail "$what (binds arrive with the overlay applied)" "not bound: $missing"
  fi
  if [[ -z "$leaked" ]]; then
    pass "$what (and are absent with no overlay applied)"
  else
    fail "$what (and are absent with no overlay applied)" "base binds them on its own: $leaked"
  fi
}

# --- Fix round 1: themes are pinned, not vendored ---------------------------

test_every_installed_theme_is_captured_or_pinned() {
  # A theme on this machine is either tracked here as files (local content, no
  # upstream to clone from) or recorded in manifests/themes.toml as remote plus
  # commit. Anything in neither place lives only on this disk.
  local manifest="$REPO_ROOT/manifests/themes.toml"
  local what="every installed omarchy theme is captured or pinned"
  local missing="" d name

  for d in "$HOME"/.config/omarchy/themes/*/; do
    [[ -d "$d" ]] || continue
    name="$(basename "$d")"
    # An empty directory is not a theme (aether is a 0-byte leftover).
    [[ -n "$(ls -A "$d" 2>/dev/null)" ]] || continue
    [[ -d "$REPO_ROOT/dotfiles/omarchy/themes/$name" ]] && continue
    grep -qx "name = \"$name\"" "$manifest" 2>/dev/null && continue
    missing+="$name "
  done

  if [[ -z "$missing" ]]; then
    pass "$what"
  else
    fail "$what" "neither tracked nor pinned: $missing"
  fi
}

test_every_theme_pin_is_reachable_offline() {
  # Network-free: the pinned commit must exist in the clone the pin was read
  # from, so a typo or a truncated sha cannot survive to Phase B.
  local manifest="$REPO_ROOT/manifests/themes.toml"
  local what="every theme pin resolves in its local clone"

  if [[ ! -f "$manifest" ]]; then
    fail "$what" "manifests/themes.toml is missing"
    return
  fi

  local bad="" seen=0 name commit
  while read -r name commit; do
    [[ -n "$name" && -n "$commit" ]] || continue
    seen=$((seen + 1))
    git -C "$HOME/.config/omarchy/themes/$name" cat-file -e "${commit}^{commit}" 2>/dev/null \
      || bad+="$name@${commit:0:8} "
  done < <(awk -F'"' '/^name = /{n=$2} /^commit = /{print n, $2}' "$manifest")

  if [[ "$seen" -eq 0 ]]; then
    fail "$what" "no [[theme]] pins found in $manifest"
  elif [[ -z "$bad" ]]; then
    pass "$what ($seen pins)"
  else
    fail "$what" "unresolvable: $bad"
  fi
}

test_no_vendored_upstream_bulk_under_captured_config() {
  # The captured tree is configuration, not asset storage. Four upstream themes
  # brought ~85 MB of backgrounds and previews in here (a single 13 MB PNG
  # among them) before they were replaced by manifests/themes.toml. Third-party
  # bulk belongs in a manifest (themes.toml, plugins.toml) or a package, the
  # same way git-filter-repo and the 8.8 MB share-picker binary already do.
  local limit=$((256 * 1024))
  local what="no vendored bulk under the captured config"
  local big="" f sz

  while IFS= read -r f; do
    [[ -f "$REPO_ROOT/$f" ]] || continue   # skips symlinks and the nvim gitlink
    sz="$(stat -c%s "$REPO_ROOT/$f" 2>/dev/null)" || continue
    [[ "$sz" -gt "$limit" ]] && big+="$f (${sz}B) "
  done < <(git -C "$REPO_ROOT" ls-files dotfiles/ home/ bin-local/ manifests/)

  if [[ -z "$big" ]]; then
    pass "$what (nothing over $((limit / 1024)) KiB)"
  else
    fail "$what" "over $((limit / 1024)) KiB: $big"
  fi
}

# --- Fix round 2: the prbuilds publication gates ----------------------------
#
# Task 6 strips the employer out of the prbuilds plugin and publishes the
# result as a PUBLIC repo. Nothing pinned that, so a half-scrubbed or
# accidentally-private repo would have shipped silently.
#
# Same three-step probe as test_work_overlay_is_private, and for the same
# reason: "cannot check" (network down, or gh unauthenticated) must never be
# conflated with "check failed" (reachable and authenticated, but the repo is
# missing, private, or dirty). Each cause is probed on its own evidence, in
# order, so a later step's failure can only mean what it claims to mean.
#
# These FAIL until the repo is actually published. That is the point: they are
# the gate, and a gate that passes before the work is done is not one.

PRBUILDS_REPO="ToRexZ/omarchy-prbuilds"
# The public git identity the user chose for their own repos on 2026-09-26,
# superseding the GitHub noreply form an earlier round assumed. Pinned here so a
# stray commit made under the global config -- which is still the employer
# address -- cannot reach a published repo unnoticed.
PRBUILDS_AUTHOR_EMAIL="victor.risager@hotmail.com"

# Returns 0 when GitHub is reachable AND gh is authenticated, so a test can
# tell "cannot check" from "check failed" in one call. Prints the reason.
_gh_can_check() {
  if ! timeout 8 gh api /zen >/dev/null 2>&1; then
    printf 'GitHub API unreachable'
    return 1
  fi
  if ! timeout 8 gh auth status >/dev/null 2>&1; then
    printf 'gh not authenticated'
    return 1
  fi
  return 0
}

test_prbuilds_is_published_public() {
  local what="prbuilds repo is published and public"
  local why
  if ! why="$(_gh_can_check)"; then
    pass "$what (skipped: $why)"
    return
  fi

  local vis rc
  vis="$(timeout 8 gh repo view "$PRBUILDS_REPO" --json visibility --jq .visibility 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    fail "$what" "gh repo view $PRBUILDS_REPO failed (exit $rc): $(printf '%s' "$vis" | head -1)"
    return
  fi
  assert_eq "PUBLIC" "$vis" "$what"
}

test_prbuilds_published_clone_is_scrubbed_and_correctly_authored() {
  # Checks the PUBLISHED artefact, not the local candidate: a clean working
  # copy on this disk says nothing about what actually reached GitHub.
  local what="published prbuilds is scrubbed in tree and history"
  local author_what="published prbuilds commits carry the associating author address"
  local why
  if ! why="$(_gh_can_check)"; then
    pass "$what (skipped: $why)"
    pass "$author_what (skipped: $why)"
    return
  fi

  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN

  local out rc
  out="$(GIT_TERMINAL_PROMPT=0 timeout 60 git clone -q \
    "https://github.com/$PRBUILDS_REPO.git" "$tmp/p" 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    # Reachable and authenticated, so a clone failure is a real finding.
    fail "$what" "git clone failed (exit $rc): $(printf '%s' "$out" | head -1)"
    fail "$author_what" "no clone to inspect"
    return
  fi

  local gate
  gate="$("$REPO_ROOT/bin/scrub-gate" "$tmp/p" 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    pass "$what"
  else
    fail "$what" "scrub-gate exit $rc: $(printf '%s' "$gate" | head -3 | tr '\n' ' ')"
  fi

  # Every commit, author and committer alike. One wrong-author commit is
  # enough, and rewriting it after publication changes every sha.
  local wrong
  wrong="$(git -C "$tmp/p" log --all --format='%ae%n%ce' | sort -u \
    | grep -vxF "$PRBUILDS_AUTHOR_EMAIL")" || true
  if [[ -z "$wrong" ]]; then
    pass "$author_what"
  else
    fail "$author_what" "unexpected address(es): $(printf '%s' "$wrong" | tr '\n' ' ')"
  fi
}

test_prbuilds_repo_name_is_already_claimed() {
  # The brief asked for this as `gh repo create ... | grep 'already exists'`.
  # That is a WRITE: run before publication it does not observe a collision,
  # it CREATES the repo -- a test that silently publishes is worse than no
  # test. The observable property is the same one `gh repo create` would trip
  # over, so it is read instead: the name resolves to a repo owned by us.
  local what="prbuilds repo name is claimed, so a re-create would collide"
  local why
  if ! why="$(_gh_can_check)"; then
    pass "$what (skipped: $why)"
    return
  fi

  local got rc
  got="$(timeout 8 gh repo view "$PRBUILDS_REPO" --json nameWithOwner --jq .nameWithOwner 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    fail "$what" "gh repo view $PRBUILDS_REPO failed (exit $rc): $(printf '%s' "$got" | head -1)"
    return
  fi
  assert_eq "$PRBUILDS_REPO" "$got" "$what"
}

# --- Fix round 1 (Task 7): a URL match is not proof the remote holds the ---
# --- commit -----------------------------------------------------------------
#
# test_patched_plugins_point_at_own_forks originally only string-matched
# `git remote get-url origin`. That passes identically whether the push
# actually landed, failed, was never run, or pushed an unrelated branch --
# exactly the failure this whole plan exists to prevent: believing work is
# safe on a remote when it is not. It now checks two independent properties
# per plugin: the URL points at the right fork, AND that fork's current
# branch genuinely holds this checkout's own HEAD commit (a read-only
# `git ls-remote`; no fetch, no push).

# Returns 0 when GitHub is reachable at all (a public, unauthenticated
# endpoint). Deliberately narrower than _gh_can_check: this test only ever
# needs anonymous git-over-https to read a public fork, so reusing
# _gh_can_check's gh-auth step would manufacture a new false "skipped" for a
# check that never needed gh auth in the first place.
_github_reachable() {
  if ! timeout 8 gh api /zen >/dev/null 2>&1; then
    printf 'GitHub unreachable'
    return 1
  fi
  return 0
}

# Checks one plugin checkout: origin URL points at the wanted fork, AND that
# fork's current branch holds this checkout's own HEAD commit. Prints a
# failure description and returns 1 if either property doesn't hold; prints
# nothing and returns 0 if both do. Factored out so it can be exercised
# directly against a scratch clone (see task-7-report.md's fix-round-1
# section) without touching the real plugin checkouts.
_plugin_fork_holds_head() {
  local dir="$1" want="$2"
  local url
  url="$(git -C "$dir" remote get-url origin 2>/dev/null || echo none)"
  if [[ "$url" != *"$want"* ]]; then
    printf '(url->%s)' "$url"
    return 1
  fi

  local branch head remote_sha
  branch="$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo HEAD)"
  head="$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo none)"
  remote_sha="$(timeout 8 git ls-remote "$url" "$branch" 2>/dev/null | cut -f1)"
  if [[ -z "$remote_sha" ]]; then
    printf "(no '%s' on remote)" "$branch"
    return 1
  fi
  if [[ "$remote_sha" != "$head" ]]; then
    printf '(remote %s=%s local=%s)' "$branch" "${remote_sha:0:7}" "${head:0:7}"
    return 1
  fi
  return 0
}

test_patched_plugins_point_at_own_forks() {
  local what="patched plugins point at their own forks and the forks hold HEAD"
  local why
  if ! why="$(_github_reachable)"; then
    pass "$what (skipped: $why)"
    return
  fi

  local bad=""
  local -A want=(
    [io.github.rvcabc.logitech]="ToRexZ/omarchy-logitech"
    [maduki-tech.omado]="ToRexZ/omado"
  )
  for p in "${!want[@]}"; do
    local dir="$HOME/.config/omarchy/plugins/$p" detail
    if ! detail="$(_plugin_fork_holds_head "$dir" "${want[$p]}")"; then
      bad+="$p$detail "
    fi
  done

  if [[ -z "$bad" ]]; then
    pass "$what"
  else
    fail "$what" "$bad"
  fi
}

test_patched_plugins_have_no_uncommitted_work() {
  local dirty=""
  for p in io.github.rvcabc.logitech maduki-tech.omado; do
    local n
    n="$(git -C "$HOME/.config/omarchy/plugins/$p" status --porcelain | wc -l)"
    [[ "$n" -eq 0 ]] || dirty+="$p($n) "
  done
  if [[ -z "$dirty" ]]; then
    pass "patched plugins have no uncommitted work"
  else
    fail "patched plugins have no uncommitted work" "$dirty"
  fi
}

# --- Task 8: the cloned built-ins (battery, power) now have real git history ---
# --- instead of existing nowhere but this disk --------------------------------

test_cloned_builtins_have_remotes() {
  local bad=""
  for p in capra_vhr.battery capra_vhr.power; do
    git -C "$HOME/.config/omarchy/plugins/$p" remote get-url origin >/dev/null 2>&1 \
      || bad+="$p "
  done
  if [[ -z "$bad" ]]; then
    pass "cloned built-ins have an origin remote"
  else
    fail "cloned built-ins have an origin remote" "no remote: $bad"
  fi
}

test_cloned_builtin_ids_are_unchanged() {
  local a b
  a="$(jq -r .id "$HOME/.config/omarchy/plugins/capra_vhr.battery/manifest.json")"
  b="$(jq -r .id "$HOME/.config/omarchy/plugins/capra_vhr.power/manifest.json")"
  assert_eq "capra_vhr.battery" "$a" "battery id unchanged"
  assert_eq "capra_vhr.power" "$b" "power id unchanged"
}

# --- Task 9: the nvim config no longer carries the employer module -----------
#
# The tooling moved to a private nvim overlay, loaded from
# ~/.config/nvim-overlays/. These two pin both halves of that split: nothing
# left behind in the public repo, and the private repo actually there to
# receive it. Neither the module paths nor the repository name is written down
# here -- both come from the overlay at runtime.

test_nvim_config_has_no_work_module() {
  local what="nvim-config carries no work module"
  local repo="$HOME/.config/nvim"

  if ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
    fail "$what" "$repo is not a git repository"
    return
  fi

  # The TRACKED tree, not the filesystem. `[[ -e ]]` answers "is it on this
  # disk", which is the wrong question twice over: a gitignored build artefact
  # would fail the test for nothing, and a file deleted from the working copy
  # but still in the index would pass it while every clone still got the
  # module. `git ls-files` reads the index, which is what a clone receives.
  #
  # The pathspecs come from the overlay's nvim/removed-paths -- one pathspec
  # per line -- rather than being written out here. Three of them name the
  # employer directly and one contains a token outright, which is how they came
  # to be assembled around an empty variable in an earlier round; the list is
  # data about one employer's tooling, so it belongs with that employer's
  # overlay and not in a public test file.
  local o list
  if ! o="$(_overlay_dir)" || [[ ! -f "$o/nvim/removed-paths" ]]; then
    pass "$what (skipped: no overlay list of removed paths)"
    return
  fi
  list="$o/nvim/removed-paths"

  local specs=() line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" || "$line" == '#'* ]] && continue
    specs+=("$line")
  done < "$list"
  if [[ ${#specs[@]} -eq 0 ]]; then
    fail "$what" "$list lists no pathspec"
    return
  fi

  local left
  left="$(git -C "$repo" ls-files -- "${specs[@]}")"

  if [[ -z "$left" ]]; then
    pass "$what"
  else
    fail "$what" "still tracked: $(printf '%s' "$left" | tr '\n' ' ')"
  fi
}

test_nvim_overlay_repo_exists_and_is_private() {
  # Same three-step shape as the other published-repo checks: "cannot check"
  # (network down, gh unauthenticated) is a skip, and only a reachable,
  # authenticated query that comes back missing or non-PRIVATE is a finding.
  local what="nvim overlay repo exists and is private"
  local repo
  if ! repo="$(_overlay_meta nvim_repo)"; then
    pass "$what (skipped: no overlay, or it declares no nvim_repo)"
    return
  fi
  local why
  if ! why="$(_gh_can_check)"; then
    pass "$what (skipped: $why)"
    return
  fi

  local vis rc
  vis="$(timeout 8 gh repo view "$repo" --json visibility --jq .visibility 2>&1)"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    fail "$what" "gh repo view $repo failed (exit $rc): $(printf '%s' "$vis" | head -1)"
    return
  fi
  assert_eq "PRIVATE" "$vis" "$what"
}

# --- Task 12: every plugin recorded as a pinned, reachable git source --------
#
# The machine has 19 plugin checkouts (not 16, and not the 18 the brief
# expected -- always re-derive from $HOME/.config/omarchy/plugins, never trust
# a stated count). bin/sync-plugins refuses to record a pin no remote can
# currently serve, so these are read straight from what it actually wrote, not
# from what it was hoped to write. A shrinking manifest is the intended failure
# mode when a real plugin regresses: it gains a commit that was never pushed,
# or loses its origin remote. Drifting BEHIND upstream is not such a regression
# and no longer refuses -- a commit in the history of a ref the remote serves
# is reachable, and treating it otherwise was a defect in the tool.

test_every_installed_plugin_is_in_the_manifest() {
  # Red while any installed plugin cannot be reinstalled from a remote. That
  # is the point: the manifest exists so a fresh machine can rebuild this one,
  # and a plugin whose HEAD lives only on this laptop breaks that promise.
  # The gap is reported with its cause so the red state is actionable rather
  # than mysterious -- never allowlisted, because an allowlist would turn a
  # real "you would lose this plugin" into a green tick.
  #
  # The egress guard on the diagnostic is `if _github_reachable; then`, not
  # `[[ -n "$(_github_reachable; echo $?)" ]]`. The latter was always true --
  # `echo $?` prints "0" or "1" and both are non-empty -- so the guard did
  # nothing and an offline run would blame a plugin for a network outage.
  local manifest="$REPO_ROOT/manifests/plugins.toml" missing=""
  for d in "$HOME"/.config/omarchy/plugins/*/; do
    local id; id="$(jq -r .id "$d/manifest.json" 2>/dev/null)"
    [[ -n "$id" && "$id" != null ]] || continue
    grep -q "id = \"$id\"" "$manifest" 2>/dev/null && continue
    local why="not recorded"
    local url; url="$(git -C "$d" remote get-url origin 2>/dev/null)" || url=""
    if [[ -z "$url" ]]; then
      why="no origin remote"
    elif _github_reachable >/dev/null 2>&1 \
      && ! "$REPO_ROOT/bin/sync-plugins" --verify "$d" "$url" \
           "$(git -C "$d" rev-parse HEAD 2>/dev/null)" >/dev/null 2>&1; then
      why="HEAD $(git -C "$d" rev-parse --short HEAD 2>/dev/null) is on no ref $url serves (push it, then re-run bin/sync-plugins)"
    fi
    missing+="$id ($why); "
  done
  if [[ -z "$missing" ]]; then
    pass "every installed plugin is in plugins.toml"
  else
    fail "every installed plugin is in plugins.toml" "missing: $missing"
  fi
}

test_every_pin_is_reachable_from_its_remote() {
  # "Reachable" means a clone of $url can produce $commit -- which is true for
  # any commit in the history of a ref the remote serves, not only for the
  # handful of commits that are ref tips today. An earlier form of this test
  # (and of bin/sync-plugins) compared tips with `ls-remote | grep -q`, and so
  # called two perfectly fetchable pins unreachable merely because upstream had
  # moved past them: agx.screen-time is 286 commits behind its remote's main,
  # bobbynicholas.omaland 3 behind, and both are genuine ancestors of it.
  #
  # The check is delegated to `bin/sync-plugins --verify` rather than
  # reimplemented here, on purpose. Tip-match-then-fetch-then-merge-base is
  # subtle enough that a second copy would drift out of step with the generator
  # silently, and a test that disagrees with the tool it is checking is worse
  # than no test -- it just tells you one of the two is wrong.
  #
  # "Cannot check" (egress down) must never be conflated with "check failed"
  # (egress fine, this specific pin doesn't resolve) -- same shape as
  # _github_reachable/_gh_can_check above: a known-public endpoint is probed
  # once for the whole test, and only a failure *there* is a skip.
  #
  # An entry marked `verified = false` is NOT silently skipped. That marker
  # means bin/sync-plugins recorded the pin from a possibly-stale local
  # remote-tracking branch because egress was down, so the manifest's own
  # reachability claim does not cover it. With egress up it is a finding in its
  # own right -- the manifest should have been regenerated -- and with egress
  # down it is named rather than folded into the skip. Before this round an
  # unverified pin was indistinguishable from a verified one in the file, and
  # this test passed-as-skip in exactly the condition that produced them.
  local manifest="$REPO_ROOT/manifests/plugins.toml"
  local what="every recorded pin is reachable from its remote"

  local unverified="" id url commit vflag
  while read -r id url commit vflag; do
    [[ "$vflag" == "false" ]] && unverified+="$id "
  done < <(_manifest_pins "$manifest")

  local why
  if ! why="$(_github_reachable)"; then
    if [[ -n "$unverified" ]]; then
      pass "$what (skipped: $why; unverified pins present and marked: $unverified)"
    else
      pass "$what (skipped: $why)"
    fi
    return
  fi

  if [[ -n "$unverified" ]]; then
    fail "$what" "egress is up but these pins are still marked verified = false (re-run bin/sync-plugins): $unverified"
    return
  fi

  local bad="" seen=0 dir
  while read -r id url commit vflag; do
    [[ -n "$id" && -n "$url" && -n "$commit" ]] || continue
    seen=$((seen + 1))
    # The plugin checkout is the object donor --verify needs to answer the
    # ancestry question: the pin lives in its objects, the remote's newer
    # history is fetched into a throwaway, and merge-base needs both together.
    # id and the checkout's directory name are the same string for every
    # plugin currently installed.
    dir="$HOME/.config/omarchy/plugins/$id"
    "$REPO_ROOT/bin/sync-plugins" --verify "$dir" "$url" "$commit" >/dev/null 2>&1 \
      || bad+="$id@${commit:0:8} "
  done < <(_manifest_pins "$manifest")

  if [[ "$seen" -eq 0 ]]; then
    fail "$what" "no [[plugin]] pins found in $manifest"
  elif [[ -z "$bad" ]]; then
    pass "$what ($seen pins)"
  else
    fail "$what" "unreachable: $bad"
  fi
}

# Prints "<id> <url> <commit> <verified>" per [[plugin]] block, where
# <verified> is "false" only for an entry carrying the `verified = false`
# marker. Block-aware rather than line-aware: the marker sits after 'commit',
# so the old print-on-the-commit-line parse could never have seen it.
_manifest_pins() {
  awk -F'"' '
    /^\[\[plugin\]\]$/       { i=""; u=""; c=""; v="true"; next }
    /^id = /                 { i=$2; next }
    /^url = /                { u=$2; next }
    /^commit = /             { c=$2; next }
    /^verified = false$/     { v="false"; next }
    /^$/                     { if (i && u && c) print i, u, c, v; i=""; u=""; c="" }
    END                      { if (i && u && c) print i, u, c, v }
  ' "$1"
}

test_an_unverifiable_pin_is_marked_and_distinguishable() {
  # bin/sync-plugins' egress-down branch, exercised deterministically against
  # a bare remote in a throwaway directory -- no network, no GitHub, nothing
  # real written to. Both states are produced from the SAME checkout, so the
  # only difference between the two manifests is what the tool knew.
  #
  # The hole this pins: when egress was down the tool fell back to a local
  # origin/* ref, recorded the pin, and exited 0, writing nothing in the file
  # to say the commit had never been checked against the remote -- while the
  # file's own header asserted every commit was reachable. It also wrote
  # `branch = "HEAD"`, because refs/remotes/origin/HEAD sorted first out of
  # `for-each-ref | head -1`, and a bootstrap would have tried to check that
  # out.
  local what="an unverifiable pin is recorded marked, and tells apart from a verified one"
  local sync="$REPO_ROOT/bin/sync-plugins"
  local t; t="$(mktemp -d)" || { fail "$what" "mktemp failed"; return; }

  (
    set -e
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
    git init -q --bare -b main "$t/remote.git"
    git clone -q "$t/remote.git" "$t/seed"
    cd "$t/seed"
    echo hi > f.txt && git add f.txt && git commit -qm c1
    git push -q origin main
    mkdir -p "$t/plugins"
    git clone -q "$t/remote.git" "$t/plugins/demo.plugin"
    cd "$t/plugins/demo.plugin"
    printf '{"id":"demo.plugin"}\n' > manifest.json
    git add manifest.json && git commit -qm manifest && git push -q origin main
  ) >/dev/null 2>&1 || { rm -rf "$t"; fail "$what" "could not build the local fixture remote"; return; }

  local err="" rc_ok rc_down

  # Egress up, remote reachable: the ordinary live path.
  PLUGINS_DIR="$t/plugins" SYNC_PLUGINS_OUT="$t/ok.toml" "$sync" >/dev/null 2>&1
  rc_ok=$?
  [[ "$rc_ok" -eq 0 ]] || err+="a live-verifiable pin exited $rc_ok; "
  grep -q '^verified = false$' "$t/ok.toml" \
    && err+="a live-verified pin was marked verified = false; "

  # Remote gone AND the egress probe pointed at a path that does not exist, so
  # "cannot check" is reached deterministically rather than "check failed".
  mv "$t/remote.git" "$t/remote-gone.git"
  SYNC_PLUGINS_EGRESS_PROBE_URL="$t/no-such-remote.git" \
    PLUGINS_DIR="$t/plugins" SYNC_PLUGINS_OUT="$t/down.toml" "$sync" >/dev/null 2>&1
  rc_down=$?

  [[ "$rc_down" -ne 0 ]] || err+="an unverifiable pin exited 0; "
  grep -q '^verified = false$' "$t/down.toml" \
    || err+="an unverifiable pin was recorded with no marker; "
  grep -q '^# UNVERIFIED:' "$t/down.toml" \
    || err+="an unverifiable pin carries no explanatory comment; "
  grep -q '^branch = "HEAD"$' "$t/down.toml" \
    && err+="recorded branch = \"HEAD\", which is not checkout-able; "
  grep -q '^id = "demo.plugin"$' "$t/down.toml" \
    || err+="the plugin was dropped from the manifest entirely; "

  # The parser the other tests use must see the difference too -- a marker
  # nothing reads is no better than a stderr line.
  [[ "$(_manifest_pins "$t/ok.toml" | awk '{print $4}')" == "true" ]] \
    || err+="_manifest_pins called the verified pin unverified; "
  [[ "$(_manifest_pins "$t/down.toml" | awk '{print $4}')" == "false" ]] \
    || err+="_manifest_pins could not tell the unverified pin apart; "

  # Same commit either way: the only difference is what the tool could prove.
  [[ "$(_manifest_pins "$t/ok.toml" | awk '{print $3}')" \
     == "$(_manifest_pins "$t/down.toml" | awk '{print $3}')" ]] \
    || err+="the two runs disagreed about the commit; "

  rm -rf "$t"
  if [[ -z "$err" ]]; then
    pass "$what"
  else
    fail "$what" "$err"
  fi
}

test_ancestry_check_accepts_a_behind_pin_and_refuses_an_unpushed_one() {
  # Both halves of the reachability rule, against a bare remote created with
  # `git init --bare` in a throwaway directory -- no network, no GitHub, no
  # write access to anything real, so this proves the rule deterministically
  # whether or not egress is up.
  #
  # The "behind" fixture is the shape bin/sync-plugins used to get WRONG:
  # a checkout parked on an older commit that the remote has since built on.
  # The "unpushed" fixture is the shape it must still refuse, and is the same
  # shape as the real mryll.meteobar / wg-omarchy findings.
  local what="ancestry check accepts a pin behind the remote tip, refuses an unpushed one"
  local scratch; scratch="$(mktemp -d)" || { fail "$what" "mktemp failed"; return; }
  local verify="$REPO_ROOT/bin/sync-plugins"
  local remote="$scratch/remote.git"
  local behind unpushed err=""

  (
    set -e
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
    git init --quiet --bare -b main "$remote"
    git clone --quiet "$remote" "$scratch/seed"
    cd "$scratch/seed"
    for n in 1 2 3; do
      echo "$n" > file.txt
      git add file.txt
      git commit --quiet -m "commit $n"
    done
    git push --quiet origin main
  ) >/dev/null 2>&1 || { rm -rf "$scratch"; fail "$what" "could not build the local fixture remote"; return; }

  # A clone parked two commits behind the remote's tip: a true ancestor.
  git clone --quiet "$remote" "$scratch/behind" >/dev/null 2>&1
  git -C "$scratch/behind" checkout --quiet HEAD~2 >/dev/null 2>&1
  behind="$(git -C "$scratch/behind" rev-parse HEAD)"

  # A clone with one further commit that was never pushed back.
  git clone --quiet "$remote" "$scratch/unpushed" >/dev/null 2>&1
  (
    cd "$scratch/unpushed"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
    export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
    echo local > file.txt
    git add file.txt
    git commit --quiet -m "never pushed"
  ) >/dev/null 2>&1
  unpushed="$(git -C "$scratch/unpushed" rev-parse HEAD)"

  "$verify" --verify "$scratch/behind" "$remote" "$behind" >/dev/null 2>&1 \
    || err+="rejected a commit that IS an ancestor of the remote tip; "
  "$verify" --verify "$scratch/unpushed" "$remote" "$unpushed" >/dev/null 2>&1 \
    && err+="accepted a commit that was never pushed; "

  # The throwaway object store the ancestry probe builds must not leave a
  # trace in the checkout it borrowed objects from.
  [[ -z "$(git -C "$scratch/behind" status --porcelain 2>/dev/null)" ]] \
    || err+="the verify pass dirtied the checkout it read from; "

  rm -rf "$scratch"
  if [[ -z "$err" ]]; then
    pass "$what"
  else
    fail "$what" "$err"
  fi
}

test_non_default_branch_pins_record_their_branch() {
  # Controller requirement: a pin whose commit is not on the remote's default
  # branch must record 'branch', or a bootstrap that clones default and checks
  # out 'commit' silently gets code that never ran here. Checked against the
  # three checkouts known to sit on a non-default ref (two forks carrying a
  # local patch on branch 'local-patch', and the private corne checkout on
  # 'keyboard-status') rather than every entry, so this doesn't regress into
  # demanding a branch field on plugins that are correctly on default.
  local manifest="$REPO_ROOT/manifests/plugins.toml"
  local what="plugins pinned off their remote's default branch record 'branch'"
  local missing="" id block
  for id in vhr.corne io.github.rvcabc.logitech maduki-tech.omado; do
    block="$(awk -v id="$id" '
      /^\[\[plugin\]\]$/ { buf=""; keep=0 }
      { buf = buf $0 ORS }
      $0 == "id = \"" id "\"" { keep=1 }
      /^$/ { if (keep) { print buf; exit } }
    ' "$manifest")"
    grep -q '^branch = "' <<<"$block" || missing+="$id "
  done
  if [[ -z "$missing" ]]; then
    pass "$what"
  else
    fail "$what" "no branch field recorded for: $missing"
  fi
}
