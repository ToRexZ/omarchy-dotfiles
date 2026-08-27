# omarchy-dotfiles

Personal config for [Omarchy](https://omarchy.org/) (Arch + Hyprland), symlinked
into `~/.config` with [stow](https://www.gnu.org/software/stow/).

## Layout

`dotfiles/` is one stow package, stowed into `~/.config` rather than `$HOME`:

```
stow --restow -d <repo> -t "$HOME/.config" dotfiles
```

stow links the *contents* of a package into the target, so each directory under
`dotfiles/` becomes the matching directory under `~/.config` and the repo does
not carry a `.config` level of its own:

| In the repo                     | Links into                     | Contents |
|---------------------------------|--------------------------------|----------|
| `dotfiles/hypr/`                | `~/.config/hypr/`              | `bindings.lua`, `monitors.lua`, `autostart.lua` |
| `dotfiles/hyprdynamicmonitors/` | `~/.config/hyprdynamicmonitors` (whole dir) | monitor profiles, one per physical location |
| `dotfiles/opencode/`            | `~/.config/opencode/`          | `opencode.json` |
| `dotfiles/herdr/`               | `~/.config/herdr/config.toml`  | terminal workspace manager keymap |

The flip side is that nothing here can land directly in `$HOME`. A `.bashrc` or
`.XCompose` would need a second package alongside `dotfiles/`, stowed with
`-t "$HOME"`.

There is also no package allowlist any more — the old script named the four
packages explicitly, this one stows whatever is under `dotfiles/`. Adding a
directory is all it takes to get it symlinked, and a stray directory gets
symlinked too, so keep `dotfiles/` free of leftovers.

Whether a directory arrives as one folded symlink or as file-by-file links is
decided by whether it already exists in `~/.config` when stow runs, so
`install-stow-packages.sh` pre-creates the ones that must stay real directories
(`hypr`, `herdr`, `opencode`) and clears the one that must fold
(`hyprdynamicmonitors`).

Omarchy drives Hyprland through Lua: `~/.config/hypr/hyprland.lua` loads
Omarchy's defaults and then `require`s `hypr.bindings`, `hypr.monitors`,
`hypr.autostart`. Files only need to exist under those names — there is nothing
to `source`. Any key Omarchy already binds must be `hl.unbind()`'d before it is
bound again.

## Monitors

Monitor layouts are managed with the **hyprdynamicmonitors TUI**, not by editing
Hyprland config:

- **`SUPER+M`** — open the TUI: drag displays, set scale, rotate, mirror, toggle VRR
- `hyprdynamicmonitors freeze --profile-name <name>` — save the current displays
  as a new profile for a new desk or meeting room

A profile is a template in `hyprconfigs/` plus a `[profiles.<name>]` entry in
`config.toml` listing the displays it requires, matched by EDID description. The
daemon watches for displays being plugged and unplugged, picks the
highest-scoring matching profile, and renders it to `~/.config/hypr/monitors.conf`.

Because the whole `~/.config/hyprdynamicmonitors` directory is a single stow
symlink, profiles created with the TUI land in this repo automatically — just
commit them. `freeze` writes `config_file` as an absolute path; rewrite it to
`$HOME/...` like the existing entries so the profile resolves for any user.

`~/.config/hypr/monitors.conf` is generated per machine and deliberately **not**
tracked here.

### How it reaches Hyprland

Two things had to be bridged, because hyprdynamicmonitors predates Omarchy's move
from `.conf` to Lua:

1. `monitors.conf` used to be picked up by a `source =` line in the now-dead
   `hyprland.conf`. `monitors.lua` reads it instead and replays each `monitor=`
   line through `hl.monitor()`, so the generated file is still the single source
   of truth the TUI and daemon share.
2. hyprdynamicmonitors applies changes live with `hyprctl keyword monitor`, which
   the Lua config provider rejects (`keyword can't work with non-legacy
   parsers`). `post_apply_exec = "hyprctl reload"` in `config.toml` re-runs
   `hyprland.lua` after each render instead.

The daemon runs as a systemd **user service**, not a Hyprland `exec-once`, so it
is ordered after `graphical-session.target`, restarts on failure, and pulls in
`hyprdynamicmonitors-prepare.service` (clears stale `monitor=...,disable` lines
at boot). Do not also start it from `autostart.lua`, or two daemons will fight
over `monitors.conf`.

```sh
systemctl --user status hyprdynamicmonitors
journalctl --user -u hyprdynamicmonitors -f
```

## herdr

`config.toml` mirrors the old tmux config: prefix is `ctrl+space`, a tmux session
is a herdr workspace, a window a tab, a pane a pane. Only `config.toml` is
symlinked — herdr keeps its sockets, logs and `session.json` in the same
directory, and those are per-machine.

herdr is built from `packages/herdr` instead of installed from the AUR, because
its keybinds panel (`prefix+?`) is unreadable with this keymap. The panel sizes
its shortcut column to the longest binding in the list, and `resize_mode` here is
a four-key alias list that renders 72 columns wide — wider than the 76-column
panel, so every description wrapped onto a row of its own at column zero, flush
left, under an indented heading.

`packages/herdr/keybind-help-readability.patch` caps that column at 40% of the
panel, gives an over-wide binding a row to itself with the description hanging in
the description column, indents entries under their group heading, puts a blank
row between entries, and widens the panel to 100x34. herdr exposes no config for
any of this, so it has to be a source patch.

The package is named `herdr-patched` and `conflicts` with `herdr` so `yay -Syu`
cannot quietly swap the patched build back out. **`herdr update` still can** — it
replaces `/usr/bin/herdr` in place — so re-run `install-scripts/herdr.sh` after
using it.

To take a new upstream release: bump `pkgver` in `packages/herdr/PKGBUILD`,
refresh the checksum with `updpkgsums`, and rebuild. If the patch stops applying,
upstream has reworked `src/ui/keybind_help.rs` and the change needs redoing.

```sh
cd packages/herdr && makepkg -si    # rebuild and install
```

## New machine

```sh
git clone git@github.com:ToRexZ/omarchy-dotfiles.git ~/omarchy_configuration/omarchy-dotfiles
cd ~/omarchy_configuration/omarchy-dotfiles
./setup-all.sh
```

`setup-all.sh` installs the packages (`install-packages.sh`) and then symlinks
config into `~/.config` (`install-stow-packages.sh`). Conflicting real files are
moved aside as `<name>.pre-stow.<timestamp>.bak` rather than deleted.

Verify afterwards:

```sh
hyprctl reload && hyprctl configerrors   # empty output = clean
hyprctl monitors all
```

`setup-github.sh` sets up an SSH key and agent for GitHub, if needed.
