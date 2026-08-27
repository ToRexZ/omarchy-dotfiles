#!/bin/sh

# Monitor layout manager. The TUI (SUPER+M) is how monitor configuration is
# edited on this setup; the daemon re-renders the matching profile whenever
# displays are plugged or unplugged.
yay -S --noconfirm --needed hyprdynamicmonitors-bin

# Run it as a systemd user service rather than a Hyprland exec-once: this orders
# it after graphical-session.target, restarts it on failure, and pulls in
# hyprdynamicmonitors-prepare.service, which clears stale `monitor=...,disable`
# lines from the generated config at boot.
systemctl --user enable --now hyprdynamicmonitors-prepare.service hyprdynamicmonitors.service
