# ~/.local/bin

Scripts stowed to `~/.local/bin`.

`hyprland-preview-share-picker` is deliberately absent: it is an 8.8 MB binary
built from upstream master because the packaged 0.2.1 mis-handles a non-zero
monitor origin. `~/.config/hypr/xdph.conf` points at it. Phase B's installer
rebuilds it from source rather than carrying the artifact.

`git-filter-repo` is also deliberately absent: it is a 210 KB third-party
script, not personal config, and belongs in a package manifest in a later
phase rather than here.
