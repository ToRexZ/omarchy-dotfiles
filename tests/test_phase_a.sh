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
