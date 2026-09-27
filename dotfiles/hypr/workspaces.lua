-- Per-monitor workspaces: keep every named workspace on the screen it is named
-- for.
--
-- mmsbrggr.per-monitor-workspaces names workspaces "<monitor description>:<slot>",
-- but a Hyprland workspace name carries no monitor affinity of its own: a named
-- workspace that does not exist yet is created on whatever monitor happens to be
-- focused. At login tenzin.auto-workspace dispatches straight to those names
-- while focus is still on one screen, so every slot it opens is born there. The
-- widget's own adopt() pass only repatriates the single workspace a screen is
-- showing and bails once it shows any of its own, so the rest stay stranded --
-- and SUPER+<slot> then follows them to the wrong screen.
--
-- Reacting to the creation rather than declaring a rule per monitor per slot is
-- deliberate: it needs no monitor enumeration at config-parse time (on a cold
-- boot the screens are not all up yet) and it avoids a fifth copy of the
-- plugin's monitor-key algorithm. Matching both the plain description and the
-- "description@connector" form the plugin falls back to for two identical panels
-- accepts whichever the name actually used, without this file having to decide
-- which case is in play.

local function monitor_for_key(key)
  for _, monitor in ipairs(hl.get_monitors()) do
    local description = monitor.description or ""
    if description ~= "" and (description == key or (description .. "@" .. monitor.name) == key) then
      return monitor
    end
  end

  return nil
end

hl.on("workspace.created", function(workspace)
  if not workspace or workspace.special then return end

  local name = workspace.name
  if type(name) ~= "string" then return end

  -- "<key>:<slot>", slot numeric. Greedy on the key so a description carrying a
  -- colon still splits at the slot. Global numbered workspaces ("3") and
  -- special:<name> do not match and are left alone.
  local key = name:match("^(.+):%d+$")
  if not key then return end

  local monitor = monitor_for_key(key)
  if not monitor then return end

  local current = workspace.monitor
  if current and current.id == monitor.id then return end

  -- Deferred, and that is the whole trick: dispatching the move from inside the
  -- creation event is silently dropped -- the workspace is still being built, so
  -- it stays put and the log shows the move issued with nothing happening.
  -- A oneshot timer lets construction finish first. Measured against the boot
  -- path rather than guessed; 50ms already worked, this leaves margin for a
  -- cold boot placing eight of these at once.
  --
  -- move, not focus: this relocates without displaying, so a workspace being
  -- born on the wrong screen never drags the user off the one they are on.
  local target = monitor.name
  hl.timer(function()
    hl.dispatch(hl.dsp.workspace.move({
      workspace = "name:" .. name,
      monitor = target,
    }))
  end, { timeout = 150, type = "oneshot" })
end)
