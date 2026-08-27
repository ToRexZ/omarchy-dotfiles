#!/bin/sh
set -e

# Submodules first. A plain `git clone` leaves dotfiles/nvim empty, and an empty
# submodule is not an error stow would notice -- it would fold ~/.config/nvim
# onto an empty directory and leave a working nvim with no config. Re-running
# this on an already-populated clone is a no-op, so it is unconditional.
echo "==> Fetching submodules"
git submodule update --init --recursive

# Install packages
. ./install-packages.sh

# Symlink config into ~/.config
./install-stow-packages.sh

# Plugins, now that ~/.config/nvim exists. LazyVim would do this on first launch
# anyway; doing it here means the first real launch is not a multi-minute clone,
# and a config that cannot load says so now rather than the first time it
# matters. Deliberately non-fatal -- everything above has already succeeded, and
# this is the one step that needs the network to cooperate.
if command -v nvim >/dev/null 2>&1; then
  echo "==> Syncing nvim plugins"
  nvim --headless "+Lazy! sync" +qa ||
    echo "  plugin sync failed -- nvim will retry on first launch" >&2
fi
