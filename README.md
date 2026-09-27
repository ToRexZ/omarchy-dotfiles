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
| `dotfiles/opencode/`            | `~/.config/opencode/`          | `opencode.json` |
| `dotfiles/herdr/`               | `~/.config/herdr/config.toml`  | terminal workspace manager keymap |
| `dotfiles/nvim/`                | `~/.config/nvim` (whole dir)   | git submodule, [ToRexZ/nvim-config](https://github.com/ToRexZ/nvim-config) |

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
(`hypr`, `herdr`, `opencode`) and clears the one that must fold (`nvim`).

Omarchy drives Hyprland through Lua: `~/.config/hypr/hyprland.lua` loads
Omarchy's defaults and then `require`s `hypr.bindings`, `hypr.monitors`,
`hypr.autostart`. Files only need to exist under those names — there is nothing
to `source`. Any key Omarchy already binds must be `hl.unbind()`'d before it is
bound again.

## Monitors

Monitor layouts are managed by
[hyprmoncfg](https://github.com/crmne/omarchy-hyprmoncfg), not by editing
Hyprland config: the `crmne.hyprmoncfg` bar widget edits and saves one profile
per setup, and `hyprmoncfgd.service` (systemd user) applies the matching one on
hotplug, lid and wake events.

hyprmoncfg writes `~/.config/hypr/hyprmoncfg-monitors.lua`, which `hyprland.lua`
loads last, and maintains a wake-settings block at the top of `monitors.lua`.
Because it rewrites `monitors.lua` in place, `~/.config/hypr/monitors.lua` ends up
a real file rather than a stow symlink; copy it back here when it changes.
`monitors.lua` itself only keeps `GDK_SCALE` and a fallback rule for displays no
profile covers.

```sh
systemctl --user status hyprmoncfgd
```

## nvim

`dotfiles/nvim` is a **git submodule**, not ordinary files — the config keeps its
own history in [ToRexZ/nvim-config](https://github.com/ToRexZ/nvim-config) and is
merely referenced from here. `~/.config/nvim` is a single folded stow symlink
into it, so the directory nvim reads is the submodule checkout itself: edits made
from either path are the same file, `lazy-lock.json` updates land in git, and
`cd ~/.config/nvim && git status` works exactly as it did before.

The superproject records a **commit pointer**, not the working tree. Committing
in the submodule is therefore only half of it — the pointer has to be moved too,
or a fresh machine gets whatever commit is recorded here:

```sh
cd dotfiles/nvim
git add -A && git commit -m "..." && git push     # 1. the config's own history
cd ../..
git add dotfiles/nvim && git commit -m "Bump nvim" # 2. the pointer in this repo
```

`git status` in this repo shows `modified: dotfiles/nvim (new commits)` whenever
the two have drifted apart. To pull someone else's bump: `git submodule update
--init --recursive`, which `setup-all.sh` runs for you.

A plain `git clone` of this repo leaves `dotfiles/nvim` **empty** — submodules
are not fetched by default. Clone with `--recurse-submodules`, or let
`setup-all.sh` do it. `install-stow-packages.sh` refuses to run against an empty
submodule rather than folding `~/.config/nvim` onto nothing.

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
git clone --recurse-submodules git@github.com:ToRexZ/omarchy-dotfiles.git ~/omarchy_configuration/omarchy-dotfiles
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
