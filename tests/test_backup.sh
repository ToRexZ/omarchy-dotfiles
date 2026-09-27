#!/usr/bin/env bash
# Backup integrity. A tarball that lists the right names but restores nothing is
# the failure mode this guards: extract and diff, never just `tar -t`.

test_backup_restores_identical_content() {
  # Skips rather than aborts when BACKUP is unset: this file is sourced by
  # every later run of tests/run.sh, and `${BACKUP:?}` under `set -u` would
  # take the whole suite down with it. But BACKUP set to a nonexistent or
  # unreadable path is a real failure, not a skip: silently passing then
  # would hide a stale/broken $BACKUP, which is exactly what this test
  # exists to catch.
  local backup="${BACKUP:-}"
  if [[ -z "$backup" ]]; then
    pass "backup check skipped (BACKUP unset)"
    return
  fi
  if [[ ! -f "$backup" ]]; then
    fail "backup contains shell.json" "BACKUP set but not a readable file: $backup"
    return
  fi
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  local tar_err
  tar_err="$(tar -xf "$backup" -C "$tmp" 2>&1 >/dev/null)"

  local probe="home/capra_vhr/.config/omarchy/shell.json"
  if [[ ! -f "$tmp/$probe" ]]; then
    if [[ -n "$tar_err" ]]; then
      fail "backup contains shell.json" "missing $probe (tar error: $tar_err)"
    else
      fail "backup contains shell.json" "missing $probe"
    fi
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
  if [[ -z "$backup" ]]; then
    pass "git-dir check skipped (BACKUP unset)"
    return
  fi
  if [[ ! -f "$backup" ]]; then
    fail "backup preserves prbuilds git history" "BACKUP set but not a readable file: $backup"
    return
  fi
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  local tar_err
  tar_err="$(tar -xf "$backup" -C "$tmp" 2>&1 >/dev/null)"
  local head="home/capra_vhr/.config/omarchy/plugins/vhr.prbuilds/.git/HEAD"

  if [[ -f "$tmp/$head" ]]; then
    pass "backup preserves prbuilds git history"
  else
    if [[ -n "$tar_err" ]]; then
      fail "backup preserves prbuilds git history" "missing $head (tar error: $tar_err)"
    else
      fail "backup preserves prbuilds git history" "missing $head"
    fi
  fi
}
