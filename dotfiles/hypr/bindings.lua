-- Personal Hyprland keybindings.
--
-- Managed in ~/omarchy_configuration/omarchy-dotfiles and symlinked to
-- ~/.config/hypr/bindings.lua, which hyprland.lua loads via
-- require("hypr.bindings") -- after Omarchy's defaults. Any key Omarchy already
-- binds must therefore be hl.unbind()'d before it is bound again.
--
-- Ported from the pre-quattro keybinds.overrides.conf, which stopped being read
-- when Omarchy moved Hyprland config from .conf to Lua.
--
-- See what is currently bound: omarchy menu keybindings --print

-- ===== Personal web apps =====
-- These take over keys Omarchy assigns to its own preinstalled apps.
--
-- Work web apps are not in this repo. An issue tracker, a wiki, a git host and
-- the office cameras used to sit here on SUPER+SHIFT+G/T/O/W; they now live in
-- a private overlay, which stows a fragment into ~/.config/hypr/bindings.d/
-- (see the loader further down). Those four keys keep Omarchy's defaults
-- unless an overlay is applied, and the fragment does its own hl.unbind()
-- before rebinding them.

hl.unbind("SUPER + SHIFT + A") -- was: ChatGPT
o.bind("SUPER + SHIFT + A", "Claude", { webapp = "https://claude.ai/new" })

hl.unbind("SUPER + SHIFT + E") -- was: Email (HEY)
o.bind("SUPER + SHIFT + E", "Email", { webapp = "https://outlook.office.com/mail/" })

hl.unbind("SUPER + SHIFT + C") -- was: Calendar (HEY)
o.bind("SUPER + SHIFT + C", "Calendar", { webapp = "https://calendar.google.com/" })

-- SUPER+ALT+H is free: the vim-nav layer owns SUPER/+SHIFT/+CTRL/+SHIFT+CTRL + H,
-- so ALT is the one H modifier combo left. H = Hailey.
o.bind("SUPER + ALT + H", "Hailey HR", { webapp = "https://haileyhr.app/" })

-- ===== Close window =====

hl.unbind("SUPER + W") -- was: Close window
o.bind("SUPER + ALT + W", "Close window", hl.dsp.window.close())

-- ===== Menus =====
-- Omarchy menu moves to SUPER+BACKSPACE, the app launcher to SUPER+R.

hl.unbind("SUPER + SPACE") -- was: Omarchy menu
hl.unbind("SUPER + ALT + SPACE") -- was: Apps menu
hl.unbind("SUPER + BACKSPACE") -- was: Toggle window transparency (new in quattro)
o.bind("SUPER + BACKSPACE", "Omarchy menu", "omarchy-menu toggle")

-- omarchy-launch-walker is gone in quattro; the app launcher is now a section
-- of the Omarchy menu.
o.bind("SUPER + R", "Launch apps", "omarchy-menu toggle apps")

-- ===== work emulator =====

o.bind(
  "SUPER + SHIFT + V",
  "Work emulator",
  os.getenv("HOME") .. "/omarchy_configuration/emulator/work_emulator_launch.sh"
)

-- ===== Email scratchpad =====
-- SUPER+E toggles a special workspace named "email", renamed from "emulator".
-- Nothing else referred to the old name: work_emulator_launch.sh above only
-- runs the emulator and never targeted that workspace.
--
-- tenzin.auto-workspace puts Outlook on special:email at login, and
-- hide_special_on_workspace_change in Omarchy's looknfeel keeps it out of the
-- way until this key brings it back.

o.bind("SUPER + E", "Toggle email workspace", hl.dsp.workspace.toggle_special("email"))

-- ===== Lock screen =====

o.bind("ALT + L", "Lock screen", "omarchy-system-lock")

-- ===== Resize windows, vim keys =====
-- Uses the native resize dispatcher rather than shelling out to
-- `hyprctl dispatch resizeactive`.

hl.unbind("SUPER + CTRL + H") -- was: Hardware menu (new in quattro)
hl.unbind("SUPER + CTRL + K") -- was: Herdr keybindings (new in quattro)
hl.unbind("SUPER + CTRL + L") -- was: Lock system (moved to ALT+L above)
o.bind("SUPER + CTRL + H", "Resize left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
o.bind("SUPER + CTRL + J", "Resize down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))
o.bind("SUPER + CTRL + K", "Resize up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
o.bind("SUPER + CTRL + L", "Resize right", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))

-- ===== Keybindings list =====
-- SUPER+SHIFT+K belongs to the workspace-to-monitor block below, so the
-- keybindings menu lives on SUPER+SHIFT+ALT+K.

hl.unbind("SUPER + K") -- was: Keybindings
o.bind("SUPER + SHIFT + ALT + K", "Keybindings", "omarchy-menu-keybindings")

-- ===== Focus windows, vim keys =====

hl.unbind("SUPER + J") -- was: Toggle window split (rebound to SUPER+I below)
hl.unbind("SUPER + L") -- was: Toggle workspace layout
o.bind("SUPER + H", "Focus left window", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + J", "Focus below window", hl.dsp.focus({ direction = "d" }))
o.bind("SUPER + K", "Focus above window", hl.dsp.focus({ direction = "u" }))
o.bind("SUPER + L", "Focus right window", hl.dsp.focus({ direction = "r" }))

-- ===== Move workspace between monitors, vim keys =====

o.bind("SUPER + SHIFT + H", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
o.bind("SUPER + SHIFT + J", "Move workspace to down monitor", hl.dsp.workspace.move({ monitor = "d" }))
o.bind("SUPER + SHIFT + K", "Move workspace to up monitor", hl.dsp.workspace.move({ monitor = "u" }))
o.bind("SUPER + SHIFT + L", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))

-- ===== Swap windows within a workspace, vim keys =====

o.bind("SUPER + CTRL + SHIFT + H", "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))
o.bind("SUPER + CTRL + SHIFT + J", "Swap window down", hl.dsp.window.swap({ direction = "d" }))
o.bind("SUPER + CTRL + SHIFT + K", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
o.bind("SUPER + CTRL + SHIFT + L", "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))

-- ===== Toggle window split =====

o.bind("SUPER + I", "Toggle window split", hl.dsp.layout("togglesplit"))

-- ===== Screenshots =====
-- Swapped from Omarchy's defaults: bare PRINT keeps the normal capture flow,
-- SHIFT+PRINT copies straight to the clipboard.

hl.unbind("PRINT") -- was: Screenshot
o.bind("PRINT", "Screenshot", "omarchy-capture-screenshot smart")
o.bind("SHIFT + PRINT", "Screenshot to clipboard", "omarchy-capture-screenshot smart copy")

-- ===== Overlay fragments =====
-- Employer keybindings are not in this repo -- they arrive as *.lua fragments
-- in ~/.config/hypr/bindings.d/, stowed there by a private overlay, and are
-- loaded here in sorted order so a fragment can unbind and rebind anything set
-- above it.
--
-- With no overlay applied the directory does not exist and this block does
-- nothing. Nothing is dofile()'d that was not just opened successfully, and
-- each fragment runs under pcall, so a missing, unreadable or broken fragment
-- costs that fragment rather than everything after it.
--
-- This sits above the per-monitor-workspaces block on purpose: that plugin
-- unbinds and rebinds SUPER+1..0 and SUPER+TAB and has to keep going last.

do
  local dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/bindings.d"
  local ls = io.popen('ls -1 "' .. dir .. '"/*.lua 2>/dev/null | sort')
  if ls then
    for path in ls:lines() do
      local probe = io.open(path, "r")
      if probe then
        probe:close()
        pcall(dofile, path)
      end
    end
    ls:close()
  end
end

-- ===== Per-monitor workspaces =====
-- Keys for the mmsbrggr.per-monitor-workspaces bar widget, which gives every
-- screen its own set of workspaces. SUPER+1..5 act on the focused screen,
-- SUPER+TAB cycles within it, SUPER+CTRL/SHIFT/ALT+arrows move focus and
-- windows between screens. The widget provides the workspaces; this only puts
-- keys on them, so it does nothing on its own if the plugin is removed.
--
-- The plugin unbinds Omarchy's global SUPER+1..0, SUPER+TAB and SUPER+CTRL+TAB
-- before rebinding them, so it has to load after everything above.
--
-- pcall so a broken or missing plugin costs these bindings rather than
-- everything that follows. Upstream asks for this line verbatim; the widget
-- greps bindings.lua for it and stops offering to add it itself.
pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/mmsbrggr.per-monitor-workspaces/hypr/init.lua")
