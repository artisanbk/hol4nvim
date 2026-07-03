--[[
  Demo / test entry point for developing hol4nvim.

  Run it isolated, without touching your real config:
      nvim -u init.lua path/to/FooScript.sml

  It bootstraps lazy.nvim and loads THIS repository as a local plugin (dir=).
  For real use you would instead add the hol4nvim spec to your own config and
  point it at the published repo ("artisanbk/hol4nvim") rather than a local
  dir, with `ft = "hol4script"` to lazy-load (see README).
--]]

-- Leaders must be set before any plugin/keymap loads. <localleader> drives the
-- HOL keymaps; with "\\" the bindings are \x \X \s \e. Change to taste.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Bootstrap lazy.nvim (clone on first run).
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

-- This repo's root: the directory containing this init.lua.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")

require("lazy").setup({
	{
		dir = root,
		name = "hol4nvim",
		-- Loaded eagerly (no ft/cmd/keys), so the plugin is on the runtimepath
		-- at startup: its ftdetect/ runs, and setup() registers the commands,
		-- before the *Script.sml argument is opened.
		config = function()
			require("hol4nvim").setup({
				abbreviations = true, -- holabs ASCII->unicode (off by default)
				-- transport = "auto",   -- "terminal" | "fifo"
				-- hol_cmd = "/path/to/bin/hol",
				-- split = "vertical",   -- "horizontal"
			})
		end,
	},
})
