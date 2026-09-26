#!/usr/bin/env bash
# Phase A capture-and-split checks. Later tasks append their own test_*
# functions here as they move, split and rewrite these repos.

test_no_untracked_config_in_base_repo() {
  local out
  out="$(git -C "$REPO_ROOT" status --porcelain -- dotfiles/ | grep '^??' || true)"
  if [[ -z "$out" ]]; then
    pass "no untracked files under dotfiles/"
  else
    fail "no untracked files under dotfiles/" "$out"
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
  local f="$REPO_ROOT/home/.XCompose"
  if grep -q 'example\.com' "$f" 2>/dev/null; then
    fail "base .XCompose has no employer address" "vhr@example.com is still in the base copy"
  else
    pass "base .XCompose has no employer address"
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
