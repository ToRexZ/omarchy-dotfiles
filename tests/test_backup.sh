#!/usr/bin/env bash
# Backup integrity. A tarball that lists the right names but restores nothing is
# the failure mode this guards: extract and diff, never just `tar -t`.

test_backup_restores_identical_content() {
  # Skips rather than aborts when BACKUP is unset: this file is sourced by
  # every later run of tests/run.sh, and `${BACKUP:?}` under `set -u` would
  # take the whole suite down with it.
  local backup="${BACKUP:-}"
  [[ -f "$backup" ]] || { pass "backup check skipped (BACKUP unset)"; return; }
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  tar -xf "$backup" -C "$tmp" 2>/dev/null

  local probe="home/capra_vhr/.config/omarchy/shell.json"
  if [[ ! -f "$tmp/$probe" ]]; then
    fail "backup contains shell.json" "missing $probe"
    return
  fi

  if diff -q "$HOME/.config/omarchy/shell.json" "$tmp/$probe" >/dev/null; then
    pass "backup restores shell.json byte-identical"
  else
    fail "backup restores shell.json byte-identical" "content differs"
  fi
}

test_backup_includes_plugin_git_dirs() {
  local backup="${BACKUP:-}" tmp
  [[ -f "$backup" ]] || { pass "git-dir check skipped (BACKUP unset)"; return; }
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  tar -xf "$backup" -C "$tmp" 2>/dev/null
  local head="home/capra_vhr/.config/omarchy/plugins/vhr.prbuilds/.git/HEAD"

  if [[ -f "$tmp/$head" ]]; then
    pass "backup preserves prbuilds git history"
  else
    fail "backup preserves prbuilds git history" "missing $head"
  fi
}
