-- Personal Hyprland display configuration.
--
-- Managed in ~/omarchy_configuration/omarchy-dotfiles and symlinked to
-- ~/.config/hypr/monitors.lua, which hyprland.lua loads via
-- require("hypr.monitors").
--
-- Monitor layouts are NOT edited here. They are managed with the
-- hyprdynamicmonitors TUI (SUPER+M), which stores one profile template per
-- physical location in ~/.config/hyprdynamicmonitors/hyprconfigs/ and renders
-- the profile matching the currently connected displays into
-- ~/.config/hypr/monitors.conf.
--
-- Omarchy moved Hyprland config from .conf to Lua, so that generated file is no
-- longer picked up by a `source =` line, and `hyprctl keyword` -- which is how
-- hyprdynamicmonitors applies changes live -- refuses to run under the Lua
-- config provider. This file closes both gaps: it reads monitors.conf and
-- replays it through hl.monitor(), and hyprdynamicmonitors is configured with
-- `post_apply_exec = "hyprctl reload"` so a rendered profile takes effect.
--
-- See the current layout:  hyprctl monitors all
-- Add or edit a location:  SUPER+M  (or `hyprdynamicmonitors tui`)

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 1.6

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Fallback for any display no generated profile covers. Declared first so the
-- per-monitor rules below take precedence.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

local generated_config = os.getenv("HOME") .. "/.config/hypr/monitors.conf"

-- Trailing `,key,value` pairs hyprdynamicmonitors can append, mapped to the
-- coercion hl.monitor() expects for each.
local trailing_options = {
  bitdepth = tonumber,
  cm = tostring,
  mirror = tostring,
  sdrbrightness = tonumber,
  sdrsaturation = tonumber,
  transform = tonumber,
  vrr = tonumber,
}

local function trim(value)
  return (value:gsub("^%s*(.-)%s*$", "%1"))
end

-- Fields are kept untrimmed: whitespace is only insignificant in the fields this
-- parser interprets, not inside a `desc:` selector that spans a comma.
local function split_fields(body)
  local fields = {}
  for field in (body .. ","):gmatch("([^,]*),") do
    table.insert(fields, field)
  end

  return fields
end

-- `monitor=<output>,<mode>,<position>,<scale>[,key,value]...`
--
-- Parsed right to left: trailing key/value pairs are peeled off first, then
-- scale, position and mode, and whatever remains is the output. Output is joined
-- back together rather than taken as field one because a `desc:` selector may
-- itself contain a comma.
local function parse_monitor_line(body)
  local fields = split_fields(body)
  if #fields == 0 then
    return nil
  end

  local spec = {}

  -- `disable` may stand alone after the output or be appended to a full monitor
  -- line, so it is removed wherever it sits before anything else is read.
  for index = #fields, 2, -1 do
    if trim(fields[index]) == "disable" then
      table.remove(fields, index)
      spec.disabled = true
    end
  end

  while #fields >= 6 do
    local key = trim(fields[#fields - 1])
    local coerce = trailing_options[key]
    if not coerce then
      break
    end

    spec[key] = coerce(trim(fields[#fields]))
    table.remove(fields)
    table.remove(fields)
  end

  if #fields >= 4 then
    local scale = trim(fields[#fields])
    spec.scale = tonumber(scale) or scale
    spec.position = trim(fields[#fields - 1])
    spec.mode = trim(fields[#fields - 2])
    for _ = 1, 3 do
      table.remove(fields)
    end
  elseif not spec.disabled then
    return nil
  end

  local output = trim(table.concat(fields, ","))
  if output == "" then
    return nil
  end

  -- A disabled output takes no mode, position or scale.
  if spec.disabled then
    return { output = output, disabled = true }
  end

  spec.output = output

  return spec
end

local file = io.open(generated_config, "r")
if file then
  for line in file:lines() do
    local body = line:match("^%s*monitor%s*=%s*(.+)$")
    if body then
      local spec = parse_monitor_line(body)
      if spec then
        hl.monitor(spec)
      end
    end
  end

  file:close()
end
