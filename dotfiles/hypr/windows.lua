-- Personal window rules. hyprland.lua requires this after Omarchy's defaults,
-- so anything here overrides them.

-- Omarchy treats Evince as a quick-preview app: default/hypr/apps/system.lua
-- tags org.gnome.Evince "+floating-window", which floats it, centres it and
-- pins it to 875x600. The PDFs opened here are specs read for long stretches
-- beside other windows, so drop the tag and tile instead.
o.window("org.gnome.Evince", { tag = "-floating-window", tile = true })
