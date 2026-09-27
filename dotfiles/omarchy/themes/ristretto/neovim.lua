-- Omarchy ships no neovim.lua for ristretto, so omarchy-theme-set falls back to
-- default/themed/neovim.lua.tpl: generic aether.nvim fed from colors.toml. That
-- palette has no real blue (Monokai Pro's ANSI blue slot is the orange #f38d70),
-- so Directory, NeoTreeDirectoryName and every @function collapse onto salmon.
-- ristretto is a Monokai Pro filter, so use the real thing instead.
--
-- Same shape as the neovim.lua the other Omarchy themes ship: pick the plugin,
-- name the colorscheme, nothing else. Transparency is applied generically to
-- whatever theme is staged, by plugin/after/transparency.lua.
return {
	{ "loctvl842/monokai-pro.nvim" },
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "monokai-pro-ristretto",
		},
	},
}
