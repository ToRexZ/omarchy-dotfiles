#!/usr/bin/env bash
#
# Symlink this repo's config into ~/.config with stow.
#
# Replaces the old install-hypr-overrides.sh, which appended `source =` lines to
# ~/.config/hypr/hyprland.conf. Omarchy now drives Hyprland through Lua
# (hyprland.lua requires hypr.bindings, hypr.monitors, ...), so there is nothing
# left to source -- the files just need to be in place under the names
# hyprland.lua already loads.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.config"
TS="$(date +%Y%m%d%H%M%S)"

# `dotfiles` is a single stow package rather than one package per app, and the
# target is ~/.config rather than $HOME. stow links the *contents* of a package
# into the target, so dotfiles/hypr/ lands as ~/.config/hypr/ and the repo does
# not have to carry a .config level of its own. Anything that belongs directly
# in $HOME (a .bashrc, say) cannot live here -- it needs a second package stowed
# with -t "$HOME".
PACKAGE="dotfiles"
PACKAGE_ROOT="$SCRIPT_DIR/$PACKAGE"

# Paths this repo claims as a whole directory rather than file by file. stow only
# folds a directory into a single symlink when the target does not already exist,
# and the fold is what makes profiles the hyprdynamicmonitors TUI creates land
# inside the repo instead of loose in ~/.config.
#
# nvim is a git submodule and has to fold for the same reason and one more: the
# fold is what keeps ~/.config/nvim a single directory with its own .git, so it
# stays a working checkout of ToRexZ/nvim-config that can be committed from
# either path. Linked file by file it would be a scatter of symlinks with no
# repo, and lazy-lock.json updates would land outside git.
DIR_CLAIMS=("hyprdynamicmonitors" "nvim")

# The inverse: paths that must stay real directories so stow links their
# contents file by file. herdr keeps its sockets, logs and session.json beside
# config.toml, and opencode keeps auth and state beside opencode.json, so a
# folded directory would write that runtime state into the repo -- and folding
# is exactly what stow does on a machine that does not have the directory yet.
# ~/.config/hypr is Omarchy's own; folding it would hide everything Omarchy put
# there.
UNFOLDED_DIRS=("herdr" "hypr" "opencode")

if ! command -v stow >/dev/null 2>&1; then
  echo "stow is not installed -- run ./install-packages.sh first" >&2
  exit 1
fi

[[ -d "$PACKAGE_ROOT" ]] || { echo "no such package: $PACKAGE_ROOT" >&2; exit 1; }

# An uninitialised submodule is an empty directory, and stow would happily fold
# ~/.config/nvim onto it -- leaving a working nvim with no config and no hint as
# to why. Catch it here instead.
if [[ -f "$SCRIPT_DIR/.gitmodules" ]]; then
  while IFS= read -r sub; do
    [[ -n "$(ls -A "$SCRIPT_DIR/$sub" 2>/dev/null)" ]] && continue
    echo "submodule $sub is empty -- run: git submodule update --init --recursive" >&2
    exit 1
  done < <(git -C "$SCRIPT_DIR" config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
fi

# A pre-existing file blocks stow. Anything that is not already a link into this
# repo gets moved aside with a timestamp rather than deleted.
displace() {
  local path="$1"

  [[ -e "$path" || -L "$path" ]] || return 0

  if [[ -L "$path" ]]; then
    local dest
    dest="$(readlink -f "$path" || true)"
    case "$dest" in
      "$SCRIPT_DIR"/*) return 0 ;;  # already ours
    esac
  fi

  echo "  displacing $path -> $(basename "$path").pre-stow.$TS.bak"
  mv "$path" "$path.pre-stow.$TS.bak"
}

is_claimed_dir() {
  local rel="$1"
  local claim
  for claim in "${DIR_CLAIMS[@]}"; do
    [[ "$rel" == "$claim" || "$rel" == "$claim"/* ]] && return 0
  done
  return 1
}

echo "==> Clearing conflicts"
for claim in "${DIR_CLAIMS[@]}"; do
  displace "$TARGET/$claim"
done

while IFS= read -r -d '' file; do
  rel="${file#"$PACKAGE_ROOT"/}"
  is_claimed_dir "$rel" && continue
  displace "$TARGET/$rel"
done < <(find "$PACKAGE_ROOT" -name .git -prune -o -type f -print0)

for dir in "${UNFOLDED_DIRS[@]}"; do
  mkdir -p "$TARGET/$dir"
done

echo "==> Stowing $PACKAGE into $TARGET"
stow -v --restow -d "$SCRIPT_DIR" -t "$TARGET" "$PACKAGE"

echo "==> Done."
echo
echo "Hyprland picks the Lua files up on its own; force a reload and check it is clean:"
echo "  hyprctl reload && hyprctl configerrors"
