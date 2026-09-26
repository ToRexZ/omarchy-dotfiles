-- Personal autostart processes.
--
-- Managed in ~/omarchy_configuration/omarchy-dotfiles and symlinked to
-- ~/.config/hypr/autostart.lua, which hyprland.lua loads via
-- require("hypr.autostart").
--
-- Ported from the pre-quattro autostart.overrides.conf, which stopped being
-- read when Omarchy moved Hyprland config from .conf to Lua.

-- o.exec_on_start is the Lua equivalent of `exec-once =`.

-- Kept from the old overrides file, still disabled:
-- o.launch_on_start("cursor")

-- The three work webapp launches that used to sit here (a wiki, an issue
-- tracker and a git host, all commented out) moved to a private overlay: see
-- its dotfiles/hypr/autostart.d/ fragment, loaded below.

-- ===== Overlay fragments =====
-- Same shape as the bindings.d loader in bindings.lua: an overlay stows *.lua
-- into ~/.config/hypr/autostart.d/ and they run here, in sorted order. With no
-- overlay applied the directory does not exist and this does nothing.

do
  local dir = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/hypr/autostart.d"
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
