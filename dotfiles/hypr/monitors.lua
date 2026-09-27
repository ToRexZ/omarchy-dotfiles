-- BEGIN hyprmoncfg wake settings
-- Shared with Omarchy while hyprmoncfg manages displays.
hl.monitor({ output = "eDP-1", mode = "preferred", position = "4352x240", scale = 2 })
-- END hyprmoncfg wake settings
-- Personal Hyprland display configuration.
--
-- Monitor layouts are NOT edited here. They are managed by hyprmoncfg (the
-- crmne.hyprmoncfg bar widget, backed by hyprmoncfgd.service), which writes
-- ~/.config/hypr/hyprmoncfg-monitors.lua. hyprland.lua loads that file last, so
-- the applied profile overrides everything in this file. hyprmoncfg also
-- maintains the wake-settings block above.
--
-- See the current layout:  hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))

-- Fallback for any display no hyprmoncfg profile covers.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })
