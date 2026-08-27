#!/bin/sh
set -e

# Install packages
. ./install-packages.sh

# Symlink config into $HOME
./install-stow-packages.sh
