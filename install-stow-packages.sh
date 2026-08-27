#!/usr/bin/env bash
#
# Symlink this repo's config into $HOME with stow.
#
# Replaces the old install-hypr-overrides.sh, which appended `source =` lines to
# ~/.config/hypr/hyprland.conf. Omarchy now drives Hyprland through Lua
# (hyprland.lua requires hypr.bindings, hypr.monitors, ...), so there is nothing
# left to source -- the files just need to be in place under the names
# hyprland.lua already loads.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$SCRIPT_DIR/dotfiles"
TARGET="$HOME"
TS="$(date +%Y%m%d%H%M%S)"

PACKAGES=(hypr hyprdynamicmonitors opencode herdr)

# Paths this repo claims as a whole directory rather than file by file. stow only
# folds a directory into a single symlink when the target does not already exist,
# and the fold is what makes profiles the hyprdynamicmonitors TUI creates land
# inside the repo instead of loose in ~/.config.
DIR_CLAIMS=(".config/hyprdynamicmonitors")

# The inverse: paths that must stay real directories so stow links their
# contents file by file. herdr keeps its sockets, logs and session.json beside
# config.toml, so a folded .config/herdr would write that runtime state into
# the repo -- and folding is exactly what stow does on a machine that has no
# ~/.config/herdr yet, which is every fresh install.
UNFOLDED_DIRS=(".config/herdr")

if ! command -v stow >/dev/null 2>&1; then
  echo "stow is not installed -- run ./install-packages.sh first" >&2
  exit 1
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

for package in "${PACKAGES[@]}"; do
  package_root="$DOTFILES/$package"
  [[ -d "$package_root" ]] || { echo "  no such package: $package" >&2; exit 1; }

  while IFS= read -r -d '' file; do
    rel="${file#"$package_root"/}"
    is_claimed_dir "$rel" && continue
    displace "$TARGET/$rel"
  done < <(find "$package_root" -type f -print0)
done

for dir in "${UNFOLDED_DIRS[@]}"; do
  mkdir -p "$TARGET/$dir"
done

echo "==> Stowing: ${PACKAGES[*]}"
cd "$DOTFILES"
stow -v --restow -t "$TARGET" "${PACKAGES[@]}"

echo "==> Done."
echo
echo "Hyprland picks the Lua files up on its own; force a reload and check it is clean:"
echo "  hyprctl reload && hyprctl configerrors"
