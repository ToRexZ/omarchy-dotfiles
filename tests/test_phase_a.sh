#!/usr/bin/env bash
# Phase A capture-and-split checks. Later tasks append their own test_*
# functions here as they move, split and rewrite these repos.

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
  local o="$HOME/omarchy_configuration/overlays/work"
  local what="work overlay matches the contract shape"

  if [[ ! -d "$o/.git" ]]; then
    fail "$what" "overlay not found at $o"
    return
  fi

  local tree
  tree="$(git -C "$o" ls-tree -r HEAD --name-only 2>&1)" || {
    fail "$what" "git ls-tree failed: $tree"
    return
  }

  local missing="" p
  grep -qxF "overlay.toml" <<<"$tree" || missing+="overlay.toml "
  for p in dotfiles home bashrc.d manifests manifests/desktop nvim install-scripts; do
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
  # also widens the check from one address to every employer token.
  local f="$REPO_ROOT/home/.XCompose"
  local what="base .XCompose has no employer address"

  # A missing file used to pass vacuously: `grep -q ... nonexistent` is
  # non-zero, which took the else branch.
  if [[ ! -f "$f" ]]; then
    fail "$what" "home/.XCompose is missing -- nothing was checked"
    return
  fi

  local tokens
  tokens="$(sed -n "s/^TOKENS='\(.*\)'$/\1/p" "$REPO_ROOT/bin/scrub-gate")"
  if [[ -z "$tokens" ]]; then
    fail "$what" "could not read TOKENS out of bin/scrub-gate"
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
  local repo="ToRexZ/omarchy-dotfiles-work"
  local what="work overlay repo is private"

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
  local frag="$HOME/omarchy_configuration/overlays/work/home/.gitconfig.d/work-email"
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
  local fragdir="$HOME/omarchy_configuration/overlays/work/home/.XCompose.d"
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
  tokens="$(sed -n "s/^TOKENS='\(.*\)'$/\1/p" "$REPO_ROOT/bin/scrub-gate")"
  if [[ -z "$tokens" ]]; then
    fail "$what" "could not read TOKENS out of bin/scrub-gate"
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
  local frag="$HOME/omarchy_configuration/overlays/work/dotfiles/hypr/bindings.d/work.lua"

  if ! command -v lua >/dev/null 2>&1; then
    pass "$what (skipped: lua not installed)"
    return
  fi
  local f
  for f in "$bindings" "$frag"; do
    if [[ ! -f "$f" ]]; then
      fail "$what" "missing: $f"
      return
    fi
  done

  local tmp; tmp="$(mktemp -d)"; trap '[[ -n "${tmp:-}" ]] && rm -rf "$tmp"; trap - RETURN' RETURN
  mkdir -p "$tmp/cfg/hypr/bindings.d" "$tmp/empty/hypr"
  cp "$frag" "$tmp/cfg/hypr/bindings.d/work.lua"

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

  local want with without
  want="$(BINDINGS="$frag" lua "$tmp/harness.lua" 2>/dev/null | sort -u)"
  if [[ -z "$want" ]]; then
    fail "$what" "the overlay fragment bound nothing -- harness or fragment is broken"
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
# The noreply address that actually associates a commit with the ToRexZ
# account (github user id 54134767). The bare ToRexZ@users.noreply.github.com
# form was invented and associates with nothing, which is what fix round 2
# caught before anything was pushed.
PRBUILDS_AUTHOR_EMAIL="54134767+ToRexZ@users.noreply.github.com"

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
