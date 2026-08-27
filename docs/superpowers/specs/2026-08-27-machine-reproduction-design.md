# Reproducing this machine from a clone

**Date:** 2026-08-27
**Status:** approved design, not yet implemented

## Goal

Clone `omarchy-dotfiles` onto a fresh Omarchy install, run one script, and end up
with this machine: the same packages, the same dotfiles, the same Omarchy
plugins and themes, the same enabled user services.

## Baseline: Omarchy is installed first

Omarchy is installed by its own installer before this repo is cloned.
`setup-all.sh` verifies it is present and stops with a clear message if not.

The alternative — carrying all 244 explicitly-installed packages so the repo is
self-contained — was rejected. Omarchy's own base list (207 packages, in
`~/.local/share/omarchy/install/omarchy-base.packages` and
`omarchy-other.packages`) changes between releases, and a duplicated copy would
rot silently. Tracking only the delta keeps the manifest at 70 packages that are
genuinely ours.

The Omarchy version this manifest was captured against is recorded in
`OMARCHY_VERSION` (currently `4.0.1-1`). `setup-all.sh` compares it to the
installed version and warns — but does not fail — on a mismatch.

## Layout

```
OMARCHY_VERSION                  4.0.1-1
packages/
  core.packages                  CLI, networking, system utilities
  dev.packages                   development toolchain
  desktop.packages               GUI applications and fonts
  robotics.packages              MQTT, point clouds, robot log viewers
  cad.packages                   CAD, slicing, GIS
  games.packages                 Steam and Minecraft launchers
  hardware.packages              drivers and firmware for THIS machine
  herdr/                         local patched herdr build (already exists)
omarchy/
  plugins.list                   id, git URL, enabled state
  themes.list                    name, git URL
dotfiles/
  hypr/                          existing
  hyprdynamicmonitors/           existing
  herdr/                         existing
  nvim/                          NEW  ~/.config/nvim
  shell/                         NEW  .bashrc .bash_profile .profile .zshrc .XCompose
  systemd/                       NEW  four user units
  omarchy/                       NEW  shell.json + the hand-made ristretto theme
install-scripts/                 existing per-tool scripts
sync-packages.sh                 NEW  reconcile manifest against what is installed
sync-omarchy.sh                  NEW  regenerate plugins.list and themes.list
install-packages.sh              rewritten to read the manifest
install-stow-packages.sh         extended package list
setup-all.sh                     full bootstrap
```

## Package groups

Groups are plain text, one package per line, `#` comments allowed. The format
matches Omarchy's own `.packages` files so the same parsing works.

`setup-all.sh` installs a default set of groups defined once at the top of the
script. The default is **all seven groups**, because the manifest describes this
machine and reproducing it is the goal; `--groups core,dev,desktop` narrows it
for a machine that should not get CAD, games or this laptop's drivers.
Everything is installed with `yay -S --needed`, which handles repo and AUR
packages uniformly — 15 of the 70 are AUR, but the installer does not need to
care which.

| Group | Count | Contents |
|---|---|---|
| `core` | 19 | bind, dmidecode, efibootmgr, fwupd, keychain, libqalculate, nmap, openbsd-netcat, rsync, sshfs, stow, tailscale, tcpdump, traceroute, tree, wireguard-tools, xmlstarlet, xorg-xrandr, yq |
| `dev` | 8 | android-studio, cursor-bin, devcontainer-cli, dotnet-runtime-9.0, github-cli, neovim, rtm-cli, rust |
| `desktop` | 17 | 1password, 1password-cli, freerdp, ghostty, google-chrome, hyprdynamicmonitors-bin, inkscape, network-manager-applet, nm-connection-editor, noto-fonts-extra, qt5-wayland, remmina, signal-desktop, spotify, ttf-cascadia-mono-nerd, typora, voxtype-bin |
| `robotics` | 4 | cloudcompare, lichtblick-bin, mqtt-explorer, mqttx-bin |
| `cad` | 4 | freecad, openscad, prusa-slicer, qgis |
| `games` | 3 | ftb-app-bin, minecraft-launcher, steam |
| `hardware` | 7 | displaylink, intel-ucode, lib32-vulkan-intel, nvidia-container-toolkit, solaar, spacenavd, supergfxctl |

Total 62 in groups, plus 8 excluded below, equals the 70-package delta.

`hardware` is the group most likely to be wrong on another machine: it assumes an
Intel CPU and GPU, a DisplayLink dock, a Logitech receiver, a 3D mouse and a
hybrid-graphics laptop. It is in the default set for this machine and is the
first thing to drop with `--groups` elsewhere.

### Deliberately excluded

| Package | Why |
|---|---|
| `omarchy`, `omarchy-keyring`, `omarchy-settings` | installed by Omarchy's own installer, not ours to manage |
| `kanshi` | superseded by hyprdynamicmonitors; a leftover that should be uninstalled |
| `yay-gzip-fix-debug` | stray debug package, not something to reinstall deliberately |
| `opencode`, `opencode-cursor-auth` | not used; the `opencode` stow package is being dropped too |
| `herdr-patched` | not installable from a repo — built locally, see below |

Excluding the two `opencode` packages is a judgement call rather than a
technical constraint. Moving them into `dev.packages` is a one-line change if
that turns out to be wrong.

### herdr

`herdr-patched` is our own build of herdr with the keybinds panel patched, and
cannot come from `yay -S`. `install-scripts/herdr.sh` already builds and
installs it from `packages/herdr`, and stays as a separate step that runs after
the manifest install. It is not listed in any `.packages` file, so
`sync-packages.sh` must know to ignore it.

## Omarchy plugins and themes

Both are git clones that Omarchy installs at runtime, so the repo records
sources rather than vendoring files.

`omarchy/plugins.list` — one plugin per line, `id<TAB>git-url<TAB>enabled|disabled`:

```
bitr0t.system-monitor                    https://github.com/rmacy/omarchy-system-monitor.git          enabled
io.github.brm-src.plugin-control-center  https://github.com/brm-src/plugin-control-center.git         enabled
io.github.rvcabc.logitech                https://github.com/rvcabc/omarchy-logitech                   enabled
jnodavid.omarkey                         https://github.com/0d4vid/omarkey.git                        enabled
maduki-tech.omado                        https://github.com/maduki-tech/omado.git                     disabled
mich.spotmarchy                          https://github.com/mich-nduka/spotmarchy.git                 enabled
mmsbrggr.per-monitor-workspaces          https://github.com/mmsbrggr/omarchy-per-monitor-workspaces.git enabled
taufderl.ipinfo                          https://github.com/taufderl/omarchy.taufderl.ipinfo.git      enabled
```

Enabled state has to be recorded separately from installation:
`maduki-tech.omado` is installed but not placed in the bar. Replay is
`omarchy plugin add <url> --yes`, then `omarchy plugin enable <id>` only for the
enabled ones.

`omarchy/themes.list` — `name<TAB>git-url`:

```
aetheria      https://github.com/JJDizz1L/aetheria.git
futurism      https://github.com/bjarneo/omarchy-futurism-theme.git
one-dark-pro  https://github.com/sc0ttman/omarchy-one-dark-pro-theme.git
pandora       https://github.com/imbypass/omarchy-pandora-theme.git
```

Replay is `omarchy theme install <url>`.

**Ristretto is not in that list.** It is the active theme and has no git remote —
it is a hand-made user override containing a single `neovim.lua`. It is vendored
into the repo as part of the `omarchy` stow package, and `setup-all.sh` sets it
as the current theme at the end.

`shell.json` holds the bar layout and per-plugin settings, and is stowed. It was
scanned for credentials and contains none, despite its `0600` mode.

## New stow packages

| Package | Links into | Notes |
|---|---|---|
| `nvim` | `~/.config/nvim` | replaces the empty `dotfiles/nvim` directory that was never listed in `PACKAGES` and so has never been stowed |
| `shell` | `~/.bashrc`, `.bash_profile`, `.profile`, `.zshrc`, `.XCompose` | stow's existing `displace()` backs up Omarchy's stock `.bashrc` before linking |
| `systemd` | `~/.config/systemd/user/` | `bt-agent.service`, `capra-build-agent.service`, `ssh-agent.service`, `voxtype.service` |
| `omarchy` | `~/.config/omarchy/` | `shell.json` and `themes/ristretto/` only |

`opencode` is removed from `PACKAGES` and its directory deleted.

### Directory folding

`install-stow-packages.sh` already has `UNFOLDED_DIRS` for exactly this hazard:
stow folds a package directory into one symlink when the target does not exist,
which on a fresh machine would put runtime state inside the repo. Three more
paths need it:

- `.config/systemd/user` — Omarchy manages `*.target.wants` symlinks in there
- `.config/omarchy` — holds Omarchy's own hooks, branding and plugin clones
- `.config/omarchy/themes` — the other four themes are git clones made at runtime

`.config/omarchy/themes/ristretto` is also unfolded, so that if Omarchy ever
writes a `backgrounds/` cache into the active theme it does not land in git.

## Sync scripts

Manifests drift. Both scripts are read-only reports by default and only write
with `--write`.

`sync-packages.sh` computes `pacman -Qqe` minus Omarchy's baseline minus the
exclusion list, then compares against the union of the group files:

```
$ ./sync-packages.sh
  + obsidian          installed, in no group
  - kanshi            in core.packages, not installed
  = 61 packages tracked and installed
  ! OMARCHY_VERSION is 4.0.1-1, installed is 4.1.0-1
```

Untracked packages are reported, never auto-assigned — only a human knows
whether something belongs in `dev` or `desktop`. `--write` removes stale entries
and appends new ones to a `# unsorted` block at the end of `core.packages` for
manual filing.

`sync-omarchy.sh` regenerates `plugins.list` and `themes.list` from
`~/.config/omarchy`, reading each clone's `git remote get-url origin` and each
plugin's enabled state from `shell.json`. A plugin or theme with no git remote is
reported as needing vendoring, the way Ristretto did.

## setup-all.sh

```
1. verify Omarchy is installed; warn if its version differs from OMARCHY_VERSION
2. install stow if missing (bootstrap: everything else needs it)
3. yay -S --needed the selected package groups
4. install-scripts/herdr.sh          (builds the patched herdr)
5. install-stow-packages.sh          (symlink dotfiles)
6. omarchy plugin add / enable       from plugins.list
7. omarchy theme install             from themes.list
8. omarchy theme set Ristretto
9. systemctl --user enable --now     the four units
10. print what needs doing by hand
```

Steps 3 and 6-9 are idempotent (`--needed`, `enable` on an already-enabled unit).
Re-running `setup-all.sh` on a configured machine must be safe.

Two flags: `--groups <list>` selects which package groups to install, and
`--dry-run` prints every command the ten steps would run without executing any
of them. `--dry-run` is what makes the plan reviewable before it touches a fresh
machine, so it must cover all ten steps, not just the package install.

## Reentrancy

Every script is safe to run any number of times, in any order, on a machine in
any state — fresh, half-configured, or complete. A second run changes nothing
and does not fail.

This matters more than it sounds. A fresh machine will not get through
`setup-all.sh` cleanly on the first attempt: the nvim clone needs an SSH key
that `setup-github.sh` has not created yet, a package mirror will be flaky, or
a plugin repo will have moved. The recovery has to be "fix it and run the whole
thing again", not "work out which of the ten steps already happened".

The rules:

- Guard before acting — check `pacman -Q`, `[[ -d ]]`, `[[ -L ]]` and skip
  rather than redo.
- Prefer natively reentrant commands: `yay -S --needed`, `stow --restow`,
  `ln -sf`, `systemctl enable --now`, `mkdir -p`.
- Never append to a tracked file without checking the entry is absent.
- A step that cannot be made reentrant detects the done state and returns early
  with a log line, not an error.
- A failure that is recoverable by hand — a clone with no SSH key — warns and
  continues, so one broken step does not block the other nine.

Three things need explicit guards rather than getting this for free: the
`--write` path of `sync-packages.sh`, which appends; `omarchy plugin add` and
`omarchy theme install`, which are not documented as no-ops on an
already-installed item; and the herdr rebuild, which is a ten-minute
from-source build that must be skipped when the installed version already
matches the PKGBUILD.

Reentrancy is verified by a test suite that runs the sync scripts and stow twice
and asserts nothing moved, plus static checks against the two bugs that are easy
to reintroduce.

## Out of scope

Not tracked, and step 10 prints them as manual follow-ups:

- **SSH keys.** `~/.ssh` holds five private keys. `setup-github.sh` already
  generates a new one; the others are per-machine. `~/.ssh/config` was
  considered and deliberately left out.
- **Credentials of any kind** — 1Password, Tailscale auth, browser profiles,
  `~/.config/Cursor`, `~/.local/share/omarchy` state.
- **`~/.config/hypr/monitors.conf`** — generated per machine by
  hyprdynamicmonitors; already untracked and staying that way.
- **Omarchy's own settings** written by `omarchy-settings`.

## Testing

The install path cannot be exercised for real without a spare machine, so
verification is structural:

- `sh -n` / `bash -n` on every script
- `sync-packages.sh` on this machine must report zero additions and zero
  removals once the manifest is written — that is the proof the groups
  reproduce the current state exactly
- `sync-omarchy.sh` must likewise produce a `plugins.list` and `themes.list`
  byte-identical to the committed ones
- `stow -n -v --restow` against a scratch target, run twice: once with the
  target directories pre-created and once without, to prove the `UNFOLDED_DIRS`
  entries actually prevent folding
- `setup-all.sh --dry-run` prints the full plan without executing it

The scratch-target stow test is the one that matters most; it is the check that
caught the `.config/herdr` folding bug.
