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
  local missing=""
  for m in windows workspaces; do
    [[ -f "$REPO_ROOT/dotfiles/hypr/$m.lua" ]] || missing+="$m "
  done
  if [[ -z "$missing" ]]; then
    pass "hyprland.lua requires resolve to tracked files"
  else
    fail "hyprland.lua requires resolve to tracked files" "missing: $missing"
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
