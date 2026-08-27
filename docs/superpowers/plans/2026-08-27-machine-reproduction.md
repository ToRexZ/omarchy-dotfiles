# Machine Reproduction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clone `omarchy-dotfiles` onto a fresh Omarchy install, run `./setup-all.sh`, and get this machine back — packages, dotfiles, Omarchy plugins and themes, user services.

**Architecture:** Plain POSIX/bash scripts over plain text manifests, matching the repo's existing idiom. Two shared libraries (`lib/common.sh`, `lib/packages.sh`) hold logic used by more than one entry point. Package groups are text files in Omarchy's own `.packages` format. Omarchy plugins, themes and the nvim config are recorded as git URLs and replayed, never vendored. A `tests/` harness of plain bash assertions proves the manifests reconcile with the live machine.

**Tech Stack:** bash, GNU stow, pacman/yay, systemd --user, `omarchy` CLI.

**Spec:** `docs/superpowers/specs/2026-08-27-machine-reproduction-design.md`

## Global Constraints

- Target machine baseline: **Omarchy 4.0.1-1**, recorded in `OMARCHY_VERSION` at repo root.
- Package manifests use Omarchy's `.packages` format: one package per line, `#` starts a comment, blank lines ignored.
- All package installs use `yay -S --needed`. Never `pacman -S` (15 of 70 packages are AUR).
- **Reentrancy is a hard requirement.** Every script must be safe to run any
  number of times, in any order, on a machine in any state — fresh, half-set-up,
  or fully configured. A second run must change nothing and must not fail.
  Concretely:
  - Guard before acting. Check whether the thing already exists (`pacman -Q`,
    `[[ -d ]]`, `[[ -L ]]`) and skip rather than redo.
  - Prefer natively reentrant commands: `yay -S --needed`, `stow --restow`,
    `ln -sf`, `systemctl enable --now`, `mkdir -p`.
  - Never append to a tracked file without first checking the entry is absent —
    an append-only write is the classic reentrancy bug.
  - A step that cannot be made reentrant must detect the already-done state and
    return early with a log line, not an error.
  - Partial failure must be resumable: re-running after a failed step picks up
    where it stopped. This is why a failed clone warns instead of aborting.
  - Task 8 is a test suite that proves this by running things twice.
- Scripts sourced by others (`install-scripts/*.sh`) must not `cd` the caller's shell and must not `set -e`.
- `#!/usr/bin/env bash` + `set -Eeuo pipefail` for standalone scripts; `#!/bin/sh` for sourced `install-scripts/*.sh`.
- Never track secrets: no private keys, no tokens, no browser profiles.
- Repo root is discovered from `BASH_SOURCE`, never assumed to be `$PWD`.

## Spec deviations discovered during planning

Three findings change what the spec described. Implement the version here.

1. **nvim is cloned, not vendored.** `~/.config/nvim` is its own git repo
   (`git@github.com:ToRexZ/nvim-config.git`, branch `master`). Vendoring it would
   nest a repo. It becomes an entry in a new `repos.list` instead of a stow package.
2. **The systemd stow package holds two files, not four.**
   `bt-agent.service` is a symlink to `/dev/null` — a *masked* unit, reproduced with
   `systemctl --user mask`. `capra-build-agent.service` is a symlink into
   `~/.config/nvim/scripts/`, reproduced as a symlink after the nvim clone.
   Only `ssh-agent.service` and `voxtype.service` are real files.
3. **`packages/excluded.packages` is a real file**, not just prose in the spec.
   `sync-packages.sh` needs it to avoid re-reporting the 8 known exclusions forever.

---

## File Structure

| File | Responsibility |
|---|---|
| `OMARCHY_VERSION` | the Omarchy release this manifest was captured against |
| `lib/common.sh` | repo root, logging, `run()` dry-run wrapper |
| `lib/packages.sh` | read manifests, read Omarchy baseline, compute deltas |
| `packages/*.packages` | seven group files |
| `packages/excluded.packages` | the 8 deliberate exclusions, with reasons |
| `omarchy/plugins.list` | plugin id, git URL, enabled state |
| `omarchy/themes.list` | theme name, git URL |
| `repos.list` | target path, git URL — for nvim |
| `dotfiles/shell/` | `.bashrc` `.bash_profile` `.profile` `.zshrc` `.XCompose` |
| `dotfiles/systemd/` | `ssh-agent.service` `voxtype.service` |
| `dotfiles/omarchy/` | `shell.json`, `themes/ristretto/` |
| `sync-packages.sh` | reconcile manifest vs installed |
| `sync-omarchy.sh` | regenerate plugins.list / themes.list |
| `install-packages.sh` | manifest-driven install (rewritten) |
| `install-stow-packages.sh` | extended PACKAGES + UNFOLDED_DIRS |
| `setup-all.sh` | the ten-step bootstrap |
| `tests/run.sh` | runs every `tests/test_*.sh` |

---

### Task 1: Shared libraries and the test harness

Nothing else can be tested until there is something to run tests with. This task
delivers the two libraries and a harness that proves they work.

**Files:**
- Create: `lib/common.sh`, `lib/packages.sh`, `tests/run.sh`, `tests/test_packages.sh`
- Create: `OMARCHY_VERSION`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `repo_root()` → absolute path to repo root
  - `log <msg>` → prints `==> msg`
  - `warn <msg>` → prints `!!! msg` to stderr
  - `die <msg>` → prints `!!! msg` to stderr, exits 1
  - `run <cmd...>` → executes, or prints `+ cmd...` when `DRY_RUN=1`
  - `read_package_file <path>` → package names on stdout, comments/blanks stripped
  - `manifest_packages <group...>` → sorted unique packages for those groups
  - `all_groups()` → group names (basename minus `.packages`, excluding `excluded`)
  - `omarchy_baseline()` → sorted unique packages from Omarchy's two base lists
  - `excluded_packages()` → sorted unique from `packages/excluded.packages`
  - `installed_delta()` → `pacman -Qqe` minus baseline minus exclusions, sorted

- [ ] **Step 1: Write the failing test**

Create `tests/test_packages.sh`:

```bash
#!/usr/bin/env bash
# Assertions over lib/packages.sh. Sourced by tests/run.sh, which provides
# assert_eq / assert_contains and counts failures.

source "$REPO_ROOT/lib/common.sh"
source "$REPO_ROOT/lib/packages.sh"

test_read_package_file_strips_comments_and_blanks() {
  local tmp; tmp="$(mktemp)"
  printf '# a comment\n\nalpha\nbeta  # trailing\n\n' > "$tmp"
  assert_eq "alpha beta" "$(read_package_file "$tmp" | tr '\n' ' ' | sed 's/ $//')" \
    "comments, trailing comments and blank lines are stripped"
  rm -f "$tmp"
}

test_omarchy_baseline_is_populated() {
  local n; n="$(omarchy_baseline | wc -l)"
  [[ "$n" -gt 100 ]] \
    && pass "omarchy baseline has $n packages" \
    || fail "omarchy baseline has $n packages, expected >100"
}

test_manifest_has_no_duplicates_across_groups() {
  local dupes
  dupes="$(manifest_packages $(all_groups) --raw | sort | uniq -d)"
  assert_eq "" "$dupes" "no package appears in two groups"
}

test_manifest_reconciles_with_this_machine() {
  local missing extra
  missing="$(comm -23 <(installed_delta) <(manifest_packages $(all_groups)))"
  extra="$(comm -13 <(installed_delta) <(manifest_packages $(all_groups)))"
  assert_eq "" "$missing" "every non-excluded installed package is in a group"
  assert_eq "" "$extra"   "every manifest package is installed"
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/run.sh`
Expected: FAIL — `tests/run.sh: No such file or directory`. Then after Step 3
creates the harness but before Step 4 creates the libs, it fails with
`lib/common.sh: No such file or directory`.

- [ ] **Step 3: Write the test harness**

Create `tests/run.sh`:

```bash
#!/usr/bin/env bash
# Plain bash test harness. Each tests/test_*.sh defines test_* functions and is
# sourced with REPO_ROOT, assert_eq, assert_contains, pass and fail available.
set -Euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

PASSED=0
FAILED=0

pass() { PASSED=$((PASSED + 1)); printf '  ok   %s\n' "$1"; }

fail() {
  FAILED=$((FAILED + 1))
  printf '  FAIL %s\n' "$1" >&2
  [[ $# -gt 1 ]] && printf '       %s\n' "$2" >&2
  return 0
}

assert_eq() {
  local want="$1" got="$2" what="$3"
  if [[ "$want" == "$got" ]]; then
    pass "$what"
  else
    fail "$what" "want: [$want]  got: [$got]"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" what="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$what"
  else
    fail "$what" "[$needle] not found in output"
  fi
}

for suite in "$REPO_ROOT"/tests/test_*.sh; do
  printf '%s\n' "--- $(basename "$suite") ---"
  # shellcheck disable=SC1090
  source "$suite"
  while IFS= read -r fn; do
    "$fn"
  done < <(declare -F | awk '{print $3}' | grep '^test_' | sort)
  # Unset so the next suite's function list is clean.
  while IFS= read -r fn; do unset -f "$fn"; done \
    < <(declare -F | awk '{print $3}' | grep '^test_')
done

printf '\n%d passed, %d failed\n' "$PASSED" "$FAILED"
[[ "$FAILED" -eq 0 ]]
```

Make it executable: `chmod +x tests/run.sh`

- [ ] **Step 4: Write the libraries**

Create `lib/common.sh`:

```bash
# Shared helpers. Sourced, never executed.

repo_root() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd
}

log()  { printf '==> %s\n' "$*"; }
warn() { printf '!!! %s\n' "$*" >&2; }
die()  { printf '!!! %s\n' "$*" >&2; exit 1; }

# Execute, or print what would run when DRY_RUN=1. Every side effect in
# setup-all.sh goes through this so --dry-run covers all ten steps, not just
# the package install.
run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    printf '  + %s\n' "$*"
  else
    "$@"
  fi
}
```

Create `lib/packages.sh`:

```bash
# Manifest and pacman queries. Requires lib/common.sh to be sourced first.

OMARCHY_INSTALL_DIR="${OMARCHY_INSTALL_DIR:-$HOME/.local/share/omarchy/install}"

# One package per line. Strips full-line and trailing comments, and blanks.
read_package_file() {
  sed -e 's/#.*//' -e 's/[[:space:]]*$//' "$1" | sed '/^$/d'
}

all_groups() {
  local f
  for f in "$(repo_root)"/packages/*.packages; do
    local name; name="$(basename "$f" .packages)"
    [[ "$name" == "excluded" ]] && continue
    printf '%s\n' "$name"
  done
}

# manifest_packages core dev            -> sorted unique
# manifest_packages core dev --raw      -> unsorted, duplicates preserved
manifest_packages() {
  local raw=0 groups=()
  local arg
  for arg in "$@"; do
    if [[ "$arg" == "--raw" ]]; then raw=1; else groups+=("$arg"); fi
  done

  local g
  for g in "${groups[@]}"; do
    local f="$(repo_root)/packages/${g}.packages"
    [[ -f "$f" ]] || die "no such package group: $g"
    read_package_file "$f"
  done | if [[ "$raw" == 1 ]]; then cat; else sort -u; fi
}

omarchy_baseline() {
  cat "$OMARCHY_INSTALL_DIR"/omarchy-base.packages \
      "$OMARCHY_INSTALL_DIR"/omarchy-other.packages 2>/dev/null \
    | sed -e 's/#.*//' | tr -s ' \t' '\n' | sed '/^$/d' | sort -u
}

excluded_packages() {
  read_package_file "$(repo_root)/packages/excluded.packages" | sort -u
}

# What this machine has that Omarchy did not install and we have not excluded.
installed_delta() {
  comm -23 \
    <(comm -23 <(pacman -Qqe | sort -u) <(omarchy_baseline)) \
    <(excluded_packages)
}
```

Create `OMARCHY_VERSION` containing exactly:

```
4.0.1-1
```

- [ ] **Step 5: Run the test to verify it now fails only on the manifest**

Run: `./tests/run.sh`
Expected: `test_read_package_file_strips_comments_and_blanks` and
`test_omarchy_baseline_is_populated` PASS; the two manifest tests FAIL because
`packages/*.packages` does not exist yet. That is correct — Task 2 creates them.

- [ ] **Step 6: Commit**

```bash
git add lib tests OMARCHY_VERSION
git commit -m "Add manifest libraries and a bash test harness"
```

---

### Task 2: Package group manifests

**Files:**
- Create: `packages/core.packages`, `dev.packages`, `desktop.packages`, `robotics.packages`, `cad.packages`, `games.packages`, `hardware.packages`, `excluded.packages`

**Interfaces:**
- Consumes: `read_package_file`, `all_groups`, `manifest_packages`, `installed_delta` (Task 1)
- Produces: the seven groups that `all_groups()` enumerates and `install-packages.sh` installs

- [ ] **Step 1: Run the failing test**

Run: `./tests/run.sh`
Expected: FAIL — `test_manifest_reconciles_with_this_machine` reports 62 missing packages.

- [ ] **Step 2: Write the group files**

`packages/core.packages`:

```
# CLI, networking and system utilities. Wanted on every machine.
bind
dmidecode
efibootmgr
fwupd
keychain
libqalculate
nmap
openbsd-netcat
rsync
sshfs
stow
tailscale
tcpdump
traceroute
tree
wireguard-tools
xmlstarlet
xorg-xrandr
yq
```

`packages/dev.packages`:

```
# Development toolchain.
android-studio
cursor-bin
devcontainer-cli
dotnet-runtime-9.0
github-cli
neovim
rtm-cli
rust
```

`packages/desktop.packages`:

```
# GUI applications and fonts.
1password
1password-cli
freerdp
ghostty
google-chrome
hyprdynamicmonitors-bin
inkscape
network-manager-applet
nm-connection-editor
noto-fonts-extra
qt5-wayland
remmina
signal-desktop
spotify
ttf-cascadia-mono-nerd
typora
voxtype-bin
```

`packages/robotics.packages`:

```
# Robotics work tooling: MQTT clients, point clouds, robot log viewers.
cloudcompare
lichtblick-bin
mqtt-explorer
mqttx-bin
```

`packages/cad.packages`:

```
# CAD, slicing and GIS.
freecad
openscad
prusa-slicer
qgis
```

`packages/games.packages`:

```
# Game launchers.
ftb-app-bin
minecraft-launcher
steam
```

`packages/hardware.packages`:

```
# Drivers and firmware for THIS machine: Intel CPU and GPU, a DisplayLink dock,
# a Logitech receiver, a 3D mouse, hybrid graphics. This is the group most
# likely to be wrong elsewhere -- drop it with --groups on other hardware.
displaylink
intel-ucode
lib32-vulkan-intel
nvidia-container-toolkit
solaar
spacenavd
supergfxctl
```

`packages/excluded.packages`:

```
# Installed here, deliberately not reproduced. sync-packages.sh reads this so
# it stops reporting them as untracked.

# Installed by Omarchy's own installer, not ours to manage.
omarchy
omarchy-keyring
omarchy-settings

# Superseded by hyprdynamicmonitors. Should be uninstalled here too.
kanshi

# Stray debug package, not something to reinstall deliberately.
yay-gzip-fix-debug

# Not used. The opencode stow package is dropped in Task 4.
opencode
opencode-cursor-auth

# Not installable from a repo -- built locally by install-scripts/herdr.sh
# from packages/herdr. See docs in that script.
herdr-patched
```

- [ ] **Step 3: Run the test to verify it passes**

Run: `./tests/run.sh`
Expected: PASS — all four `test_packages.sh` assertions, including
`every non-excluded installed package is in a group` and
`every manifest package is installed`. This is the proof the groups reproduce
the current machine exactly.

- [ ] **Step 4: Commit**

```bash
git add packages/*.packages
git commit -m "Add package group manifests

Seven groups plus an exclusion list. Verified against the machine: the 62
grouped and 8 excluded packages reconcile exactly with the delta between
pacman -Qqe and Omarchy's base lists."
```

---

### Task 3: sync-packages.sh

**Files:**
- Create: `sync-packages.sh`
- Modify: `tests/test_packages.sh` (append the sync tests)

**Interfaces:**
- Consumes: `installed_delta`, `manifest_packages`, `all_groups`, `log`, `warn` (Task 1); the group files (Task 2)
- Produces: `./sync-packages.sh [--write]`, exit 0 when in sync, 1 when drifted

- [ ] **Step 1: Write the failing test**

Append to `tests/test_packages.sh`:

```bash
test_sync_packages_reports_in_sync_on_this_machine() {
  local out; out="$("$REPO_ROOT/sync-packages.sh" 2>&1)"; local rc=$?
  assert_eq "0" "$rc" "sync-packages.sh exits 0 when the manifest matches"
  assert_contains "$out" "in sync" "sync-packages.sh says it is in sync"
}

test_sync_packages_flags_a_missing_package() {
  # A package in the manifest that is not installed must be reported.
  local out
  out="$(MANIFEST_EXTRA_FOR_TEST=definitely-not-a-real-package \
         "$REPO_ROOT/sync-packages.sh" 2>&1)" || true
  assert_contains "$out" "definitely-not-a-real-package" \
    "a manifest package that is not installed is reported"
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/run.sh`
Expected: FAIL — `sync-packages.sh: No such file or directory`.

- [ ] **Step 3: Write sync-packages.sh**

```bash
#!/usr/bin/env bash
#
# Reconcile the package manifest against what is actually installed.
#
# Read-only by default. --write removes entries that are no longer installed
# and appends new ones to an "# unsorted" block in core.packages for filing by
# hand -- only a human knows whether something belongs in dev or desktop.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"

WRITE=0
[[ "${1:-}" == "--write" ]] && WRITE=1

groups=$(all_groups)
tracked=$(manifest_packages $groups)

# Test hook: pretend an extra package is in the manifest.
if [[ -n "${MANIFEST_EXTRA_FOR_TEST:-}" ]]; then
  tracked=$(printf '%s\n%s\n' "$tracked" "$MANIFEST_EXTRA_FOR_TEST" | sort -u)
fi

installed=$(installed_delta)

untracked=$(comm -23 <(printf '%s\n' "$installed") <(printf '%s\n' "$tracked"))
stale=$(comm -13 <(printf '%s\n' "$installed") <(printf '%s\n' "$tracked"))

drift=0

while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  printf '  + %-28s installed, in no group\n' "$p"
  drift=1
done <<< "$untracked"

while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  printf '  - %-28s in the manifest, not installed\n' "$p"
  drift=1
done <<< "$stale"

n_tracked=$(printf '%s\n' "$tracked" | sed '/^$/d' | wc -l)
printf '  = %s packages tracked\n' "$n_tracked"

# Warn when the recorded Omarchy baseline no longer matches the machine, since
# the delta is only meaningful against the version it was captured on.
recorded="$(cat "$SCRIPT_DIR/OMARCHY_VERSION" 2>/dev/null || echo unknown)"
current="$(pacman -Q omarchy 2>/dev/null | awk '{print $2}' || echo unknown)"
if [[ "$recorded" != "$current" ]]; then
  warn "OMARCHY_VERSION is $recorded, installed is $current"
fi

if [[ "$drift" -eq 0 ]]; then
  log "manifest is in sync"
  exit 0
fi

UNSORTED_HEADER='# unsorted -- file these into the right group'

if [[ "$WRITE" -eq 1 ]]; then
  # Drop stale entries. Package names contain '.', '+' and digits, so match them
  # as fixed whole lines -- a sed regex would let "dotnet-runtime-9.0" also
  # match "dotnet-runtime-9x0".
  if [[ -n "$(printf '%s\n' "$stale" | sed '/^$/d')" ]]; then
    for f in "$SCRIPT_DIR"/packages/*.packages; do
      grep -Fxv -f <(printf '%s\n' "$stale" | sed '/^$/d') "$f" > "$f.tmp" || true
      mv "$f.tmp" "$f"
    done
  fi

  # Append untracked ones for manual filing. This is reentrant twice over: once
  # appended a package is tracked, so the next run finds nothing to add, and the
  # header is only written when absent, so repeated runs cannot stack up copies.
  if [[ -n "$(printf '%s\n' "$untracked" | sed '/^$/d')" ]]; then
    core_file="$SCRIPT_DIR/packages/core.packages"
    grep -Fxq "$UNSORTED_HEADER" "$core_file" \
      || printf '\n%s\n' "$UNSORTED_HEADER" >> "$core_file"
    printf '%s\n' "$untracked" | sed '/^$/d' >> "$core_file"
    log "appended untracked packages to packages/core.packages under '# unsorted'"
  fi
  log "manifest updated"
  exit 0
fi

warn "manifest has drifted -- re-run with --write to update"
exit 1
```

Make it executable: `chmod +x sync-packages.sh`

- [ ] **Step 4: Run the test to verify it passes**

Run: `./tests/run.sh`
Expected: PASS — both sync tests, plus the four from Task 2 still passing.

- [ ] **Step 5: Commit**

```bash
git add sync-packages.sh tests/test_packages.sh
git commit -m "Add sync-packages.sh to catch manifest drift"
```

---

### Task 4: Omarchy plugin and theme manifests

**Files:**
- Create: `omarchy/plugins.list`, `omarchy/themes.list`, `sync-omarchy.sh`, `tests/test_omarchy.sh`

**Interfaces:**
- Consumes: `log`, `warn`, `die` (Task 1)
- Produces: `./sync-omarchy.sh [--write]`; the two list files consumed by `setup-all.sh` in Task 7

- [ ] **Step 1: Write the failing test**

Create `tests/test_omarchy.sh`:

```bash
#!/usr/bin/env bash
# Assertions over the Omarchy plugin and theme manifests.

source "$REPO_ROOT/lib/common.sh"

test_plugins_list_matches_installed_plugins() {
  local listed installed
  listed="$(awk 'NF && $1 !~ /^#/ {print $1}' "$REPO_ROOT/omarchy/plugins.list" | sort)"
  installed="$(cd "$HOME/.config/omarchy/plugins" && ls -d */ 2>/dev/null | sed 's#/##' | sort)"
  assert_eq "$installed" "$listed" "plugins.list lists exactly the installed plugins"
}

test_every_plugin_has_a_git_url_and_state() {
  local bad
  bad="$(awk 'NF && $1 !~ /^#/ && ($2 !~ /^https?:/ || $3 !~ /^(enabled|disabled)$/) {print $1}' \
         "$REPO_ROOT/omarchy/plugins.list")"
  assert_eq "" "$bad" "every plugin row has a git URL and enabled|disabled"
}

test_omado_is_recorded_as_disabled() {
  # Installed but not placed in the bar -- the case that proves enabled state
  # is tracked separately from installation.
  local state
  state="$(awk '$1 == "maduki-tech.omado" {print $3}' "$REPO_ROOT/omarchy/plugins.list")"
  assert_eq "disabled" "$state" "maduki-tech.omado is recorded as disabled"
}

test_ristretto_is_not_in_themes_list() {
  # It is hand-made with no git remote, so it is vendored instead (Task 5).
  local hit
  hit="$(awk '$1 == "ristretto" {print $1}' "$REPO_ROOT/omarchy/themes.list")"
  assert_eq "" "$hit" "ristretto is vendored, not listed as a git theme"
}

test_sync_omarchy_reports_in_sync() {
  local out; out="$("$REPO_ROOT/sync-omarchy.sh" 2>&1)"; local rc=$?
  assert_eq "0" "$rc" "sync-omarchy.sh exits 0 when the lists match"
  assert_contains "$out" "in sync" "sync-omarchy.sh says it is in sync"
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/run.sh`
Expected: FAIL — `omarchy/plugins.list` does not exist.

- [ ] **Step 3: Write the manifests**

`omarchy/plugins.list` — whitespace-separated `id  git-url  enabled|disabled`:

```
# Omarchy shell plugins. Replayed with `omarchy plugin add <url> --yes`, then
# `omarchy plugin enable <id>` for the enabled ones. Enabled state is tracked
# separately because a plugin can be installed without being placed in the bar.
# Regenerate with ./sync-omarchy.sh --write
bitr0t.system-monitor                    https://github.com/rmacy/omarchy-system-monitor.git             enabled
io.github.brm-src.plugin-control-center  https://github.com/brm-src/plugin-control-center.git            enabled
io.github.rvcabc.logitech                https://github.com/rvcabc/omarchy-logitech                      enabled
jnodavid.omarkey                         https://github.com/0d4vid/omarkey.git                           enabled
maduki-tech.omado                        https://github.com/maduki-tech/omado.git                        disabled
mich.spotmarchy                          https://github.com/mich-nduka/spotmarchy.git                    enabled
mmsbrggr.per-monitor-workspaces          https://github.com/mmsbrggr/omarchy-per-monitor-workspaces.git  enabled
taufderl.ipinfo                          https://github.com/taufderl/omarchy.taufderl.ipinfo.git         enabled
```

`omarchy/themes.list` — `name  git-url`:

```
# Omarchy themes installed from git. Replayed with `omarchy theme install <url>`.
# The active theme, Ristretto, is NOT here -- it is hand-made with no remote and
# is vendored as part of the omarchy stow package.
# Regenerate with ./sync-omarchy.sh --write
aetheria      https://github.com/JJDizz1L/aetheria.git
futurism      https://github.com/bjarneo/omarchy-futurism-theme.git
one-dark-pro  https://github.com/sc0ttman/omarchy-one-dark-pro-theme.git
pandora       https://github.com/imbypass/omarchy-pandora-theme.git
```

- [ ] **Step 4: Write sync-omarchy.sh**

```bash
#!/usr/bin/env bash
#
# Regenerate omarchy/plugins.list and omarchy/themes.list from what is
# installed under ~/.config/omarchy.
#
# Read-only by default; --write updates the files. A plugin or theme with no git
# remote cannot be replayed on another machine and is reported as needing
# vendoring -- that is how the hand-made Ristretto theme was found.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

OMARCHY_CONFIG="${OMARCHY_CONFIG:-$HOME/.config/omarchy}"
SHELL_JSON="$OMARCHY_CONFIG/shell.json"

WRITE=0
[[ "${1:-}" == "--write" ]] && WRITE=1

needs_vendoring=()

generate_plugins() {
  cat <<'HEADER'
# Omarchy shell plugins. Replayed with `omarchy plugin add <url> --yes`, then
# `omarchy plugin enable <id>` for the enabled ones. Enabled state is tracked
# separately because a plugin can be installed without being placed in the bar.
# Regenerate with ./sync-omarchy.sh --write
HEADER
  local dir id url state
  for dir in "$OMARCHY_CONFIG"/plugins/*/; do
    [[ -d "$dir" ]] || continue
    id="$(basename "$dir")"
    url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$url" ]]; then
      needs_vendoring+=("plugin:$id")
      continue
    fi
    # A plugin is enabled when its id appears in the bar layout.
    if grep -q "\"id\": \"$id\"" "$SHELL_JSON" 2>/dev/null; then
      state=enabled
    else
      state=disabled
    fi
    printf '%-40s %-62s %s\n' "$id" "$url" "$state"
  done
}

generate_themes() {
  cat <<'HEADER'
# Omarchy themes installed from git. Replayed with `omarchy theme install <url>`.
# The active theme, Ristretto, is NOT here -- it is hand-made with no remote and
# is vendored as part of the omarchy stow package.
# Regenerate with ./sync-omarchy.sh --write
HEADER
  local dir name url
  for dir in "$OMARCHY_CONFIG"/themes/*/; do
    [[ -d "$dir" ]] || continue
    name="$(basename "$dir")"
    url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
    if [[ -z "$url" ]]; then
      needs_vendoring+=("theme:$name")
      continue
    fi
    printf '%-13s %s\n' "$name" "$url"
  done
}

new_plugins="$(generate_plugins)"
new_themes="$(generate_themes)"

for item in "${needs_vendoring[@]:-}"; do
  [[ -z "$item" ]] && continue
  warn "$item has no git remote -- it must be vendored into the repo"
done

if [[ "$WRITE" -eq 1 ]]; then
  printf '%s\n' "$new_plugins" > "$SCRIPT_DIR/omarchy/plugins.list"
  printf '%s\n' "$new_themes"  > "$SCRIPT_DIR/omarchy/themes.list"
  log "omarchy manifests updated"
  exit 0
fi

drift=0
diff -q <(printf '%s\n' "$new_plugins") "$SCRIPT_DIR/omarchy/plugins.list" >/dev/null 2>&1 \
  || { warn "omarchy/plugins.list is out of date"; drift=1; }
diff -q <(printf '%s\n' "$new_themes") "$SCRIPT_DIR/omarchy/themes.list" >/dev/null 2>&1 \
  || { warn "omarchy/themes.list is out of date"; drift=1; }

if [[ "$drift" -eq 0 ]]; then
  log "omarchy manifests are in sync"
  exit 0
fi

warn "re-run with --write to update"
exit 1
```

Make it executable: `chmod +x sync-omarchy.sh`

- [ ] **Step 5: Run the test to verify it passes**

Run: `./tests/run.sh`
Expected: PASS — all five `test_omarchy.sh` assertions. If
`test_sync_omarchy_reports_in_sync` fails on whitespace, regenerate the files
with `./sync-omarchy.sh --write` and commit the generated form; the generator is
the source of truth for the formatting.

- [ ] **Step 6: Commit**

```bash
git add omarchy sync-omarchy.sh tests/test_omarchy.sh
git commit -m "Record Omarchy plugins and themes as git sources

Eight plugins and four themes, replayed rather than vendored. Enabled state
is tracked separately: maduki-tech.omado is installed but not in the bar."
```

---

### Task 5: New stow packages and the folding guards

**Files:**
- Create: `dotfiles/shell/.bashrc`, `.bash_profile`, `.profile`, `.zshrc`, `.XCompose`
- Create: `dotfiles/systemd/.config/systemd/user/ssh-agent.service`, `voxtype.service`
- Create: `dotfiles/omarchy/.config/omarchy/shell.json`
- Create: `dotfiles/omarchy/.config/omarchy/themes/ristretto/neovim.lua`
- Delete: `dotfiles/nvim/` (empty, never stowed), `dotfiles/opencode/`
- Modify: `install-stow-packages.sh` (`PACKAGES`, `UNFOLDED_DIRS`)
- Create: `tests/test_stow.sh`

**Interfaces:**
- Consumes: nothing from earlier tasks
- Produces: stow packages `shell`, `systemd`, `omarchy` that Task 7 relies on being stowed

- [ ] **Step 1: Write the failing test**

Create `tests/test_stow.sh`:

```bash
#!/usr/bin/env bash
# Stow behaviour. The critical case is a target directory that does not exist:
# stow folds a package directory into a single symlink when the target is
# missing, which would put runtime state inside the repo. This is the check
# that caught the .config/herdr folding bug.

source "$REPO_ROOT/lib/common.sh"

# Run stow in simulation against a scratch target and return its plan.
stow_plan() {
  local target="$1" package="$2"
  (cd "$REPO_ROOT/dotfiles" && stow -n -v --restow -t "$target" "$package" 2>&1)
}

test_omarchy_package_never_folds_the_config_dir() {
  local target; target="$(mktemp -d)"
  mkdir -p "$target/.config/omarchy/themes/ristretto"
  local plan; plan="$(stow_plan "$target" omarchy)"
  assert_contains "$plan" ".config/omarchy/shell.json" "shell.json is linked individually"
  if [[ "$plan" == *"LINK: .config/omarchy "* ]]; then
    fail "omarchy config dir must not be folded into one symlink"
  else
    pass "omarchy config dir is not folded"
  fi
  rm -rf "$target"
}

test_systemd_package_never_folds_the_user_dir() {
  local target; target="$(mktemp -d)"
  mkdir -p "$target/.config/systemd/user"
  local plan; plan="$(stow_plan "$target" systemd)"
  assert_contains "$plan" "ssh-agent.service" "ssh-agent.service is linked"
  if [[ "$plan" == *"LINK: .config/systemd/user "* ]]; then
    fail "systemd user dir must not be folded into one symlink"
  else
    pass "systemd user dir is not folded"
  fi
  rm -rf "$target"
}

test_unfolded_dirs_covers_every_hazard() {
  local decl; decl="$(grep '^UNFOLDED_DIRS=' "$REPO_ROOT/install-stow-packages.sh")"
  local d
  for d in .config/herdr .config/systemd/user .config/omarchy .config/omarchy/themes; do
    assert_contains "$decl" "$d" "UNFOLDED_DIRS covers $d"
  done
}

test_packages_list_is_current() {
  local decl; decl="$(grep '^PACKAGES=' "$REPO_ROOT/install-stow-packages.sh")"
  local p
  for p in hypr hyprdynamicmonitors herdr shell systemd omarchy; do
    assert_contains "$decl" "$p" "PACKAGES includes $p"
  done
  if [[ "$decl" == *opencode* ]]; then
    fail "opencode should have been dropped from PACKAGES"
  else
    pass "opencode is no longer stowed"
  fi
  if [[ "$decl" == *nvim* ]]; then
    fail "nvim is cloned via repos.list, not stowed"
  else
    pass "nvim is not a stow package"
  fi
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/run.sh`
Expected: FAIL — `stow: ERROR: The stow directory ... does not contain package omarchy`.

- [ ] **Step 3: Populate the stow packages from the live machine**

```bash
cd "$(git rev-parse --show-toplevel)"

mkdir -p dotfiles/shell
cp ~/.bashrc ~/.bash_profile ~/.profile ~/.zshrc ~/.XCompose dotfiles/shell/

mkdir -p dotfiles/systemd/.config/systemd/user
cp ~/.config/systemd/user/ssh-agent.service \
   ~/.config/systemd/user/voxtype.service \
   dotfiles/systemd/.config/systemd/user/

mkdir -p dotfiles/omarchy/.config/omarchy/themes/ristretto
cp ~/.config/omarchy/shell.json dotfiles/omarchy/.config/omarchy/
cp ~/.config/omarchy/themes/ristretto/neovim.lua \
   dotfiles/omarchy/.config/omarchy/themes/ristretto/

git rm -r --cached dotfiles/opencode 2>/dev/null || true
rm -rf dotfiles/opencode dotfiles/nvim
```

`bt-agent.service` and `capra-build-agent.service` are deliberately not copied —
they are a mask and a symlink, reproduced by `setup-all.sh` in Task 7.

Verify `shell.json` still contains no credentials before committing:

```bash
grep -icE "token|secret|password|api[_-]?key|bearer" dotfiles/omarchy/.config/omarchy/shell.json
```

Expected output: `0`. If it is not 0, stop and re-scope what gets tracked.

- [ ] **Step 4: Update install-stow-packages.sh**

Replace the `PACKAGES` line:

```bash
PACKAGES=(hypr hyprdynamicmonitors herdr shell systemd omarchy)
```

Replace the `UNFOLDED_DIRS` block with:

```bash
# The inverse: paths that must stay real directories so stow links their
# contents file by file. Folding is what stow does when the target does not
# exist, which is every fresh install.
#
#   .config/herdr           sockets, logs and session.json live beside config.toml
#   .config/systemd/user    Omarchy manages *.target.wants symlinks in here
#   .config/omarchy         Omarchy's own hooks, branding and plugin clones
#   .config/omarchy/themes  the other four themes are git clones made at runtime
UNFOLDED_DIRS=(
  ".config/herdr"
  ".config/systemd/user"
  ".config/omarchy"
  ".config/omarchy/themes"
)
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `./tests/run.sh`
Expected: PASS — all of `test_stow.sh`.

Then run the real stow simulation against your own home to confirm nothing
unexpected is displaced:

```bash
cd dotfiles && stow -n -v --restow -t "$HOME" hypr hyprdynamicmonitors herdr shell systemd omarchy
```

Expected: `LINK:` lines only for the files listed above. No `LINK: .config/omarchy `
or `LINK: .config/systemd/user ` bare-directory lines.

- [ ] **Step 6: Commit**

```bash
git add -A dotfiles install-stow-packages.sh tests/test_stow.sh
git commit -m "Add shell, systemd and omarchy stow packages

Drops the unused opencode package and the empty dotfiles/nvim that was never
listed in PACKAGES. Three new UNFOLDED_DIRS entries stop stow folding
directories that hold Omarchy and systemd runtime state."
```

---

### Task 6: repos.list and the nvim clone

**Files:**
- Create: `repos.list`, `install-scripts/repos.sh`
- Modify: `tests/test_stow.sh` (append the repos test)

**Interfaces:**
- Consumes: `log`, `warn`, `run` (Task 1)
- Produces: `clone_repos()` in `install-scripts/repos.sh`, called by `setup-all.sh` step 5

- [ ] **Step 1: Write the failing test**

Append to `tests/test_stow.sh`:

```bash
test_repos_list_has_nvim_with_an_ssh_url() {
  local url
  url="$(awk '$1 == ".config/nvim" {print $2}' "$REPO_ROOT/repos.list")"
  assert_eq "git@github.com:ToRexZ/nvim-config.git" "$url" \
    "repos.list clones the nvim config from its own repo"
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/run.sh`
Expected: FAIL — `awk: can't open file .../repos.list`.

- [ ] **Step 3: Write repos.list**

```
# Configs that are their own git repositories. Cloned rather than vendored, so
# they stay independently versioned and updatable.
#
#   target-path-relative-to-$HOME    git-url    branch
#
# These use SSH, so they need the GitHub key from setup-github.sh. A clone that
# fails is reported as a manual follow-up rather than aborting the whole setup.
.config/nvim    git@github.com:ToRexZ/nvim-config.git    master
```

- [ ] **Step 4: Write install-scripts/repos.sh**

```bash
#!/bin/sh
#
# Clone the configs that are their own git repositories. Sourced by
# setup-all.sh, so no `set -e` and no cd that escapes a subshell.
#
# A failed clone is almost always a missing SSH key on a fresh machine. That is
# recoverable by hand, so it is reported and skipped rather than fatal.

clone_repos() {
  repos_file="$1"
  failed=""

  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac

    target=$(printf '%s\n' "$line" | awk '{print $1}')
    url=$(printf '%s\n' "$line" | awk '{print $2}')
    branch=$(printf '%s\n' "$line" | awk '{print $3}')
    dest="$HOME/$target"

    if [ -d "$dest/.git" ]; then
      log "$target already cloned"
      continue
    fi

    if [ -e "$dest" ]; then
      warn "$dest exists and is not a git checkout -- skipping"
      failed="$failed $target"
      continue
    fi

    log "cloning $url -> $target"
    if ! run git clone --branch "$branch" "$url" "$dest"; then
      warn "could not clone $url"
      failed="$failed $target"
    fi
  done < "$repos_file"

  if [ -n "$failed" ]; then
    warn "clone these by hand once SSH access works:$failed"
  fi
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `./tests/run.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add repos.list install-scripts/repos.sh tests/test_stow.sh
git commit -m "Clone the nvim config instead of vendoring it

~/.config/nvim is its own repo (ToRexZ/nvim-config); vendoring it would nest
a git repo inside this one."
```

---

### Task 7: install-packages.sh and setup-all.sh

**Files:**
- Modify: `install-packages.sh` (full rewrite)
- Modify: `setup-all.sh` (full rewrite)
- Delete: `install-scripts/jq.sh`, `yq.sh`, `nmap.sh`, `stow.sh`
- Create: `tests/test_setup.sh`

**Interfaces:**
- Consumes: everything from Tasks 1-6
- Produces: `./setup-all.sh [--groups a,b,c] [--dry-run]`

`install-scripts/{jq,yq,nmap,stow}.sh` are one-line `yay -S` wrappers whose
packages are now in the manifest (`jq` is already in Omarchy's baseline, so it
was always redundant). `hyprdynamicmonitors.sh` and `herdr.sh` stay — they do
more than install a package.

- [ ] **Step 1: Write the failing test**

Create `tests/test_setup.sh`:

```bash
#!/usr/bin/env bash
# setup-all.sh must be reviewable before it touches a machine, so --dry-run has
# to cover all ten steps, not just the package install.

source "$REPO_ROOT/lib/common.sh"

test_dry_run_touches_nothing_and_covers_every_step() {
  local out; out="$("$REPO_ROOT/setup-all.sh" --dry-run 2>&1)"; local rc=$?
  assert_eq "0" "$rc" "--dry-run exits 0"
  assert_contains "$out" "yay -S --needed"        "step 3 package install is planned"
  assert_contains "$out" "install-stow-packages"  "step 6 stow is planned"
  assert_contains "$out" "omarchy plugin add"     "step 7 plugins are planned"
  assert_contains "$out" "omarchy theme install"  "step 8 themes are planned"
  assert_contains "$out" "omarchy theme set"      "step 9 sets the active theme"
  assert_contains "$out" "systemctl"              "step 10 enables user services"
}

test_groups_flag_narrows_the_install() {
  local out; out="$("$REPO_ROOT/setup-all.sh" --dry-run --groups core 2>&1)"
  assert_contains "$out" "stow"  "core group still installs stow"
  if [[ "$out" == *"steam"* ]]; then
    fail "--groups core must not install games"
  else
    pass "--groups core excludes the games group"
  fi
}

test_unknown_group_is_rejected() {
  local out rc
  out="$("$REPO_ROOT/setup-all.sh" --dry-run --groups nonesuch 2>&1)" && rc=0 || rc=$?
  assert_eq "1" "$rc" "an unknown group name exits 1"
  assert_contains "$out" "nonesuch" "the bad group name is named in the error"
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/run.sh`
Expected: FAIL — `setup-all.sh: unrecognized option '--dry-run'`.

- [ ] **Step 3: Rewrite install-packages.sh**

```bash
#!/usr/bin/env bash
#
# Install the package manifest. Groups default to all of them; the goal is to
# reproduce this machine, and narrowing is the exception.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"

install_package_groups() {
  local groups=("$@")
  local pkgs
  pkgs="$(manifest_packages "${groups[@]}")"

  log "installing $(printf '%s\n' "$pkgs" | wc -l) packages from: ${groups[*]}"
  # shellcheck disable=SC2086
  run yay -S --noconfirm --needed $pkgs
}

# Runnable directly as well as sourced.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  mapfile -t _groups < <(all_groups)
  install_package_groups "${_groups[@]}"
fi
```

- [ ] **Step 4: Rewrite setup-all.sh**

```bash
#!/usr/bin/env bash
#
# Reproduce this machine on top of a fresh Omarchy install.
#
#   ./setup-all.sh                          everything
#   ./setup-all.sh --groups core,dev        only those package groups
#   ./setup-all.sh --dry-run                print the plan, change nothing
#
# Every step is idempotent; re-running on a configured machine is a no-op.
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/packages.sh"
source "$SCRIPT_DIR/install-scripts/repos.sh"

DRY_RUN=0
GROUPS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --groups)  GROUPS="$2"; shift ;;
    *)         die "unknown argument: $1" ;;
  esac
  shift
done
export DRY_RUN

if [[ -n "$GROUPS" ]]; then
  IFS=',' read -r -a groups <<< "$GROUPS"
  known="$(all_groups)"
  for g in "${groups[@]}"; do
    grep -qx "$g" <<< "$known" || die "unknown package group: $g (have: $(echo $known))"
  done
else
  mapfile -t groups < <(all_groups)
fi

# 1. Omarchy must already be installed; the manifest is only the delta on top.
log "checking Omarchy"
command -v omarchy >/dev/null 2>&1 \
  || die "Omarchy is not installed -- install it first, then re-run this"
recorded="$(cat "$SCRIPT_DIR/OMARCHY_VERSION")"
current="$(pacman -Q omarchy 2>/dev/null | awk '{print $2}' || echo unknown)"
[[ "$recorded" == "$current" ]] \
  || warn "manifest captured on Omarchy $recorded, this machine has $current"

# 2. stow bootstraps everything else.
command -v stow >/dev/null 2>&1 || run yay -S --noconfirm --needed stow

# 3. Packages.
source "$SCRIPT_DIR/install-packages.sh"
install_package_groups "${groups[@]}"

# 4. herdr, built locally from the patched source. Skipped when the installed
#    version already matches the PKGBUILD -- a from-source rebuild takes ten
#    minutes and re-running setup must not pay that twice.
want_herdr="$(awk -F= '/^pkgver=/{print $2}' "$SCRIPT_DIR/packages/herdr/PKGBUILD")"
have_herdr="$(pacman -Q herdr-patched 2>/dev/null | awk '{print $2}' | cut -d- -f1 || true)"
if [[ "$want_herdr" == "$have_herdr" ]]; then
  log "herdr-patched $have_herdr already installed"
else
  log "building patched herdr"
  ( cd "$SCRIPT_DIR" && source "$SCRIPT_DIR/install-scripts/herdr.sh" )
fi

# 5. Configs that are their own git repositories.
log "cloning config repos"
clone_repos "$SCRIPT_DIR/repos.list"

# 6. Dotfiles.
log "stowing dotfiles"
run "$SCRIPT_DIR/install-stow-packages.sh"

# 7. Omarchy plugins. `omarchy plugin add` on an already-cloned plugin is not
#    guaranteed to be a no-op, so guard on the clone directory. `plugin enable`
#    is safe to repeat.
#    Note the explicit if/fi: `[[ ... ]] && run ...` would return 1 for every
#    disabled plugin and kill the script under `set -e`.
log "installing Omarchy plugins"
while read -r id url state; do
  case "$id" in ''|'#'*) continue ;; esac
  if [[ -d "$HOME/.config/omarchy/plugins/$id" ]]; then
    log "plugin $id already installed"
  else
    run omarchy plugin add "$url" --yes
  fi
  if [[ "$state" == "enabled" ]]; then
    run omarchy plugin enable "$id"
  fi
done < "$SCRIPT_DIR/omarchy/plugins.list"

# 8. Omarchy themes, guarded the same way.
log "installing Omarchy themes"
while read -r name url; do
  case "$name" in ''|'#'*) continue ;; esac
  if [[ -d "$HOME/.config/omarchy/themes/$name" ]]; then
    log "theme $name already installed"
  else
    run omarchy theme install "$url"
  fi
done < "$SCRIPT_DIR/omarchy/themes.list"

# 9. The active theme is the vendored one, stowed in step 6.
run omarchy theme set Ristretto

# 10. User services. bt-agent is a mask; capra-build-agent lives in the nvim
#     repo cloned in step 5.
log "enabling user services"
run systemctl --user daemon-reload
run systemctl --user mask bt-agent.service
if [[ -f "$HOME/.config/nvim/scripts/capra-build-agent.service" ]]; then
  run ln -sf "$HOME/.config/nvim/scripts/capra-build-agent.service" \
             "$HOME/.config/systemd/user/capra-build-agent.service"
  run systemctl --user enable --now capra-build-agent.service
else
  warn "nvim repo missing -- capra-build-agent.service not linked"
fi
run systemctl --user enable --now ssh-agent.service voxtype.service
run systemctl --user enable --now hyprdynamicmonitors-prepare.service hyprdynamicmonitors.service

cat <<'MANUAL'

==> Done. Still to do by hand:
      - SSH keys: run ./setup-github.sh, then re-run to clone anything skipped
      - sign in: 1Password, Tailscale (sudo tailscale up), Chrome, Signal, Spotify
      - monitors: open the hyprdynamicmonitors TUI with SUPER+M
      - verify Hyprland: hyprctl reload && hyprctl configerrors
MANUAL
```

- [ ] **Step 5: Delete the redundant install scripts**

```bash
git rm install-scripts/jq.sh install-scripts/yq.sh install-scripts/nmap.sh install-scripts/stow.sh
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `./tests/run.sh`
Expected: PASS — all of `test_setup.sh`, and every earlier suite still green.

Then read the plan yourself:

```bash
./setup-all.sh --dry-run | head -60
```

Expected: ten labelled steps, every side effect prefixed `+`, nothing executed.

- [ ] **Step 7: Commit**

```bash
git add -A install-packages.sh setup-all.sh install-scripts tests/test_setup.sh
git commit -m "Drive setup-all.sh from the manifest

Ten idempotent steps with --groups and --dry-run. Drops four install-scripts
that were one-line yay wrappers now covered by the manifest."
```

---

### Task 8: Reentrancy

Everything above claims to be safe to re-run. This task proves it by running
things twice and asserting nothing moved, and adds static guards against the two
reentrancy bugs that are easy to reintroduce.

**Files:**
- Create: `tests/test_reentrancy.sh`

**Interfaces:**
- Consumes: `sync-packages.sh` (T3), `sync-omarchy.sh` (T4), `install-stow-packages.sh` (T5), `setup-all.sh` (T7)
- Produces: nothing

- [ ] **Step 1: Write the failing test**

Create `tests/test_reentrancy.sh`:

```bash
#!/usr/bin/env bash
# Everything here must be safe to run repeatedly. These tests run things twice
# and assert nothing changed the second time.

source "$REPO_ROOT/lib/common.sh"

test_sync_packages_write_is_a_noop_when_in_sync() {
  "$REPO_ROOT/sync-packages.sh" --write >/dev/null 2>&1 || true
  "$REPO_ROOT/sync-packages.sh" --write >/dev/null 2>&1 || true
  local diff; diff="$(git -C "$REPO_ROOT" status --porcelain -- packages/)"
  assert_eq "" "$diff" "two sync-packages.sh --write runs leave packages/ untouched"
}

test_sync_omarchy_write_is_a_noop_when_in_sync() {
  "$REPO_ROOT/sync-omarchy.sh" --write >/dev/null 2>&1 || true
  "$REPO_ROOT/sync-omarchy.sh" --write >/dev/null 2>&1 || true
  local diff; diff="$(git -C "$REPO_ROOT" status --porcelain -- omarchy/)"
  assert_eq "" "$diff" "two sync-omarchy.sh --write runs leave omarchy/ untouched"
}

test_dry_run_output_is_stable_across_runs() {
  local a b
  a="$("$REPO_ROOT/setup-all.sh" --dry-run 2>&1)"
  b="$("$REPO_ROOT/setup-all.sh" --dry-run 2>&1)"
  assert_eq "$a" "$b" "setup-all.sh --dry-run prints the same plan twice"
}

test_stow_restow_plan_is_stable() {
  local target; target="$(mktemp -d)"
  mkdir -p "$target/.config/omarchy/themes/ristretto" "$target/.config/systemd/user"
  local a b
  a="$(cd "$REPO_ROOT/dotfiles" && stow -n -v --restow -t "$target" omarchy systemd 2>&1)"
  b="$(cd "$REPO_ROOT/dotfiles" && stow -n -v --restow -t "$target" omarchy systemd 2>&1)"
  assert_eq "$a" "$b" "stow --restow plans identically on a repeat run"
  rm -rf "$target"
}

test_no_unguarded_conditional_run_under_set_e() {
  # `[[ cond ]] && run ...` returns 1 when cond is false, which kills a script
  # running under `set -e`. Every conditional side effect must use if/fi.
  local hits
  hits="$(grep -n ']] && run' "$REPO_ROOT/setup-all.sh" || true)"
  assert_eq "" "$hits" "no '[[ ... ]] && run' in setup-all.sh"
}

test_omarchy_installs_are_guarded() {
  # Both must be preceded by an existence check, or a re-run redoes the work.
  local body; body="$(cat "$REPO_ROOT/setup-all.sh")"
  assert_contains "$body" 'if [[ -d "$HOME/.config/omarchy/plugins/$id" ]]' \
    "plugin install is guarded on the clone directory"
  assert_contains "$body" 'if [[ -d "$HOME/.config/omarchy/themes/$name" ]]' \
    "theme install is guarded on the theme directory"
}

test_herdr_rebuild_is_guarded_on_version() {
  local body; body="$(cat "$REPO_ROOT/setup-all.sh")"
  assert_contains "$body" 'pacman -Q herdr-patched' \
    "herdr rebuild is skipped when the installed version already matches"
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/run.sh`
Expected: FAIL on whichever guards are missing. If Tasks 3, 4 and 7 were
implemented exactly as written, the static-check tests pass immediately and only
the run-twice tests exercise anything new — that is fine, they are the
regression net for future edits.

- [ ] **Step 3: Fix anything the suite catches**

Work through each failure. The likely ones:
- a `[[ ... ]] && run` that slipped back in → convert to `if`/`fi`
- `sync-*.sh --write` producing a diff → the generator's formatting does not
  match the committed file; regenerate with `--write` and commit the generated
  form, since the generator is the source of truth
- an unstable `--dry-run` → something in the plan is reading live state that
  changes between runs; make it read the manifest instead

- [ ] **Step 4: Run the full suite to verify everything passes**

Run: `./tests/run.sh`
Expected: PASS — every suite, `0 failed`.

- [ ] **Step 5: Confirm the tree is clean**

The reentrancy tests deliberately run `--write`. Make sure they changed nothing:

```bash
git status --porcelain
```

Expected: only `tests/test_reentrancy.sh` as a new file. If `packages/` or
`omarchy/` show modifications, a `--write` path is not reentrant — fix it before
committing.

- [ ] **Step 6: Commit**

```bash
git add tests/test_reentrancy.sh
git commit -m "Prove the setup scripts are reentrant

Runs the sync scripts and stow twice and asserts nothing moves, plus static
guards against the two bugs that are easy to reintroduce: an unguarded
'[[ ... ]] && run' that aborts under set -e, and unguarded omarchy plugin
and theme installs that redo work on every run."
```

---

### Task 9: README

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: everything
- Produces: nothing

- [ ] **Step 1: Rewrite the "New machine" section**

Replace it with:

````markdown
## New machine

Install Omarchy first — this repo layers on top of it and does not duplicate its
207-package base list.

```sh
git clone git@github.com:ToRexZ/omarchy-dotfiles.git ~/omarchy_configuration/omarchy-dotfiles
cd ~/omarchy_configuration/omarchy-dotfiles
./setup-all.sh --dry-run    # read the plan first
./setup-all.sh
```

`--groups core,dev,desktop` narrows the install. Drop `hardware` on anything
that is not this laptop: it assumes an Intel CPU and GPU, a DisplayLink dock, a
Logitech receiver, a 3D mouse and hybrid graphics.

`setup-all.sh` is reentrant: run it as many times as you like, on a fresh
machine or a fully configured one. Every step guards on whether its work is
already done, so a second run changes nothing and finishes in seconds. If a step
fails — most often a clone that needs an SSH key you have not set up yet — fix
the cause and just run it again; it picks up where it stopped.

Verify afterwards:

```sh
hyprctl reload && hyprctl configerrors   # empty output = clean
./tests/run.sh                           # manifests still match the machine
```

## Keeping the manifest honest

Both scripts report by default and only change files with `--write`.

```sh
./sync-packages.sh     # packages installed vs packages tracked
./sync-omarchy.sh      # Omarchy plugins and themes vs what is recorded
```

Run them after installing something worth keeping. `sync-packages.sh --write`
appends unknown packages to `packages/core.packages` under `# unsorted` for you
to file into the right group by hand.
````

- [ ] **Step 2: Add a Packages section after the Layout table**

````markdown
## Packages

`packages/*.packages` holds the 70 packages this machine has that Omarchy did
not install, in seven groups: `core` `dev` `desktop` `robotics` `cad` `games`
`hardware`. `packages/excluded.packages` records the ones deliberately left out
and why, so `sync-packages.sh` stops flagging them.

Everything installs with `yay -S --needed`; 15 of the 70 are AUR packages but
the installer does not distinguish. `herdr-patched` is the exception — it is
built locally, see the herdr section below.
````

- [ ] **Step 3: Add the Omarchy plugins/themes section**

````markdown
## Omarchy plugins and themes

Recorded as git URLs in `omarchy/plugins.list` and `omarchy/themes.list`, not
vendored, so they update normally. Plugin enabled-state is tracked separately
from installation because a plugin can be installed without being placed in the
bar.

The active theme, **Ristretto**, is the exception: it is hand-made with no git
remote, so it is vendored in the `omarchy` stow package.
````

- [ ] **Step 4: Update the Layout table**

Replace the table body with:

````markdown
| Package             | Links into                     | Contents |
|---------------------|--------------------------------|----------|
| `hypr`              | `~/.config/hypr/`              | `bindings.lua`, `monitors.lua`, `autostart.lua` |
| `hyprdynamicmonitors` | `~/.config/hyprdynamicmonitors` (whole dir) | monitor profiles, one per physical location |
| `herdr`             | `~/.config/herdr/config.toml`  | terminal workspace manager keymap |
| `shell`             | `~/.bashrc` and friends        | `.bashrc`, `.bash_profile`, `.profile`, `.zshrc`, `.XCompose` |
| `systemd`           | `~/.config/systemd/user/`      | `ssh-agent.service`, `voxtype.service` |
| `omarchy`           | `~/.config/omarchy/`           | `shell.json`, the vendored Ristretto theme |

`~/.config/nvim` is not a stow package — it is its own repository, cloned from
`repos.list`.
````

- [ ] **Step 5: Verify and commit**

```bash
./tests/run.sh
git add README.md
git commit -m "Document the reproduce-a-machine workflow"
```

---

## Self-Review

**Spec coverage.** Every section of the design maps to a task: baseline check
(T7 step 1), `OMARCHY_VERSION` (T1), the seven groups (T2), exclusions (T2),
herdr special-casing (T2 exclusion + T7 step 4), plugins and themes (T4),
Ristretto vendoring (T5), new stow packages (T5), folding guards (T5), sync
scripts (T3, T4), the ten-step `setup-all.sh` with `--groups` and `--dry-run`
(T7), out-of-scope manual follow-ups (T7 closing heredoc), and the testing
strategy (T1 harness, exercised throughout). Reentrancy is T8. README is T9.

**Reentrancy audit.** Every side effect in the plan was checked against the
Global Constraints rule, and three genuine breaks were found and fixed:
`sync-packages.sh --write` appended an `# unsorted` header on every run
(now written only when absent, and its `sed`-based deletion was replaced with a
fixed-string match because package names contain `.`); `omarchy plugin add` and
`omarchy theme install` redid work on every run (now guarded on the clone
directory); and `install-scripts/herdr.sh` triggered a ten-minute from-source
rebuild every time (now skipped when the installed version matches the
PKGBUILD). A fourth, unrelated bug surfaced during the same pass:
`[[ "$state" == "enabled" ]] && run ...` returns 1 for every disabled plugin,
which under `set -e` would have aborted `setup-all.sh` at `maduki-tech.omado` —
the one disabled plugin in the manifest. It is now `if`/`fi`, and T8 has a
static test so it cannot come back.

Naturally reentrant and left alone: `yay -S --needed`, `stow --restow` (its
`displace()` already returns early for links it owns), `ln -sf`, `mkdir -p`,
`systemctl enable --now`, `systemctl mask`, `clone_repos` (guards on
`.git`), and `sync-omarchy.sh --write` (regenerates wholesale rather than
appending).

**Spec deviations,** all recorded at the top of this plan and reflected in the
tasks: nvim is cloned not stowed (T6), the systemd package holds two files
rather than four (T5), and `packages/excluded.packages` is a real file (T2).
The spec should be amended to match after this plan is executed.

**Placeholders.** None. Every code step contains the file's full contents or an
exact replacement block.

**Type consistency.** `manifest_packages`, `all_groups`, `installed_delta`,
`excluded_packages`, `omarchy_baseline`, `read_package_file`, `run`, `log`,
`warn`, `die` and `clone_repos` are each defined once and used with the same
signature everywhere. `install_package_groups` is defined in
`install-packages.sh` (T7) and called from `setup-all.sh` (T7) only.
