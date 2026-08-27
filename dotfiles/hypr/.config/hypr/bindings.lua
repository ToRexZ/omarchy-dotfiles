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

-- ===== Capra web apps =====
-- These take over keys Omarchy assigns to its own preinstalled apps.

hl.unbind("SUPER + SHIFT + G") -- was: Signal
o.bind("SUPER + SHIFT + G", "Bitbucket", { webapp = "https://bitbucket.org/CapraRobotics/workspace/overview/" })

-- SUPER+SHIFT+T is free in Omarchy's defaults, so no unbind is needed.
o.bind("SUPER + SHIFT + T", "Jira", { webapp = "https://caprarobotics.atlassian.net/jira/software/c/projects/CSW/boards/51" })

hl.unbind("SUPER + SHIFT + O") -- was: Obsidian
o.bind("SUPER + SHIFT + O", "Confluence", { webapp = "https://caprarobotics.atlassian.net/wiki/home" })

hl.unbind("SUPER + SHIFT + W") -- was: Omawrite
o.bind(
  "SUPER + SHIFT + W",
  "Webcams",
  { webapp = "https://unifi.ui.com/consoles/0CEA1412855100000000085F228E0000000008D11CE00000000066FE3236:2131503338/protect/dashboard/all" }
)

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

-- ===== VDA commander emulator =====

o.bind(
  "SUPER + SHIFT + V",
  "VDA-Commander emulator",
  os.getenv("HOME") .. "/omarchy_configuration/emulator/vda_commander_launch.sh"
)
o.bind("SUPER + E", "Toggle emulator workspace", hl.dsp.workspace.toggle_special("emulator"))

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

-- ===== Monitor config TUI =====

o.bind("SUPER + M", "Monitor config", "omarchy-launch-tui hyprdynamicmonitors tui")

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
