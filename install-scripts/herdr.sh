#!/bin/sh

# Terminal workspace manager. Built from packages/herdr rather than pulled from
# the AUR, because the stock keybinds panel (prefix+?) is unreadable with the
# keymap in dotfiles/herdr/.config/herdr/config.toml.
#
# The panel sizes its shortcut column to the longest binding in the list. Our
# resize_mode is a four-key alias list that renders 72 columns wide, which
# overflowed the 76-column panel, so ratatui wrapped every description onto a
# row of its own at column zero -- flush left, under an indented heading.
# packages/herdr/keybind-help-readability.patch caps the column, gives an
# over-wide binding its own row with the description hanging in the description
# column, indents entries under their group, puts a blank row between them and
# widens the panel. Upstream exposes no config for any of this.
#
# The package is named herdr-patched and conflicts with herdr so `yay -Syu`
# cannot quietly swap the patched build back out. `herdr update` still can --
# it replaces /usr/bin/herdr in place -- so re-run this script after using it.
yay -S --noconfirm --needed zig0.15-bin rust

# Sourced from install-packages.sh, so keep the cd and any failure inside a
# subshell instead of leaking them into the caller's shell.
(
  cd packages/herdr || exit 1
  makepkg -si --noconfirm --needed
)
