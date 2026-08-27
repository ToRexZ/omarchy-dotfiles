#!/bin/sh

# Editor. The config itself is the dotfiles/nvim submodule, symlinked to
# ~/.config/nvim by install-stow-packages.sh -- this only puts the binary and the
# tools the config shells out to in place.
#
# Omarchy already ships every one of these, so on a stock install this is a
# no-op. It is listed anyway so the repo does not silently depend on that: the
# config is LazyVim, and without ripgrep and fd its pickers come up empty with
# no error worth reading.
yay -S --noconfirm --needed \
  neovim \
  ripgrep \
  fd \
  fzf \
  lazygit \
  unzip
