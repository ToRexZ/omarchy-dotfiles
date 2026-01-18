#!/usr/bin/env bash
set -Eeuo pipefail

# ----------------------------
# Config
# ----------------------------
STOW_PACKAGE="hypr"
STOW_TARGET="$HOME"

HYPRLAND_CONFIG="$HOME/.config/hypr/hyprland.conf"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HYPR_DOTFILES_ROOT="$(cd -- "$SCRIPT_DIR/dotfiles" && pwd)"

# Where override files live *inside the repo*
OVERRIDES_DIR="$HYPR_DOTFILES_ROOT/hypr/.config/hypr"

# ----------------------------
# Functions
# ----------------------------
add_source() {
  local file="$1"
  local source_line="source = $file"

  if grep -Fxq -- "$source_line" "$HYPRLAND_CONFIG"; then
    echo "Already sourced: $file"
    return 0
  fi

  echo "Sourcing: $file"
  [[ -s "$HYPRLAND_CONFIG" ]] && printf '\n' >> "$HYPRLAND_CONFIG"
  printf '%s\n' "$source_line" >> "$HYPRLAND_CONFIG"
}

# ----------------------------
# Preconditions
# ----------------------------
if [[ ! -f "$HYPRLAND_CONFIG" ]]; then
  echo "Hyprland config not found: $HYPRLAND_CONFIG" >&2
  exit 1
fi

if [[ ! -d "$OVERRIDES_DIR" ]]; then
  echo "Overrides directory not found: $OVERRIDES_DIR" >&2
  exit 1
fi

# ----------------------------
# Stow
# ----------------------------
echo "Stowing '$STOW_PACKAGE' → $STOW_TARGET"
cd "$HYPR_DOTFILES_ROOT"
stow -v -t "$STOW_TARGET" "$STOW_PACKAGE"

# ----------------------------
# Source all override files
# ----------------------------
mapfile -t override_files < <(
  find "$OVERRIDES_DIR" \
    -maxdepth 1 \
    -type f \
    -name '*.conf' \
    ! -name 'hyprland.conf' \
    -print \
  | sort
)

if (( ${#override_files[@]} == 0 )); then
  echo "No override .conf files found"
  exit 0
fi

for f in "${override_files[@]}"; do
  add_source "$f"
done

echo "Hyprland overrides installed successfully"
