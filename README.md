# omarchy-dotfiles

Personal config for [Omarchy](https://omarchy.org/) (Arch + Hyprland), symlinked
into `$HOME` with [stow](https://www.gnu.org/software/stow/).

## Layout

| Package             | Links into                     | Contents |
|---------------------|--------------------------------|----------|
| `hypr`              | `~/.config/hypr/`              | `bindings.lua`, `monitors.lua`, `autostart.lua` |
| `hyprdynamicmonitors` | `~/.config/hyprdynamicmonitors` (whole dir) | monitor profiles, one per physical location |
| `opencode`          | `~/.config/opencode/`          | `opencode.json` |

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

## New machine

```sh
git clone git@github.com:ToRexZ/omarchy-dotfiles.git ~/omarchy_configuration/omarchy-dotfiles
cd ~/omarchy_configuration/omarchy-dotfiles
./setup-all.sh
```

`setup-all.sh` installs the packages (`install-packages.sh`) and then symlinks
config into `$HOME` (`install-stow-packages.sh`). Conflicting real files are
moved aside as `<name>.pre-stow.<timestamp>.bak` rather than deleted.

Verify afterwards:

```sh
hyprctl reload && hyprctl configerrors   # empty output = clean
hyprctl monitors all
```

`setup-github.sh` sets up an SSH key and agent for GitHub, if needed.
