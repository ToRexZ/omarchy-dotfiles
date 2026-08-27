#!/bin/sh
set -e

# Pull in submodules (dotfiles/nvim). Harmless when they are already present, and
# the only thing standing between a plain `git clone` and a working nvim.
git submodule update --init --recursive

# Install packages
. ./install-packages.sh

# Symlink config into ~/.config
./install-stow-packages.sh
