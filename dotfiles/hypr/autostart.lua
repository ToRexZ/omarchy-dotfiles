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
-- o.exec_on_start(o.launch_webapp("https://exampleorg.atlassian.net/wiki/home"))
-- o.exec_on_start(o.launch_webapp("https://exampleorg.atlassian.net/jira/for-you"))
-- o.exec_on_start(o.launch_webapp("https://bitbucket.org/ExampleOrg/workspace/overview/"))
