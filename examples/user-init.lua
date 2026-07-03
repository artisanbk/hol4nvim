--[[
  Example user config for hol4nvim -- copy into ~/.config/nvim/init.lua, or
  merge the plugin spec into your existing lazy.nvim plugin list.

  The plugin derives everything from one root. If `hol` is already
  discoverable -- on $PATH, via a .HOLMK/lastmaker next to your script, or
  through an exported $HOLDIR -- the setup({}) needs NO options at all.
  Otherwise set `holdir` and stop: the hol binary (<holdir>/bin/hol),
  holdeptool for \l, the default fifo path, and vimhol.sml for the REPL
  auto-bootstrap are all found from it. Paths may use "~".
--]]

-- Leaders must be set before any plugin loads. <localleader> prefixes every
-- HOL keymap: with " " the send map is <Space>s, with "h" it is hs.
vim.g.mapleader = " "
vim.g.maplocalleader = " "

-- Bootstrap lazy.nvim (clones it on first run).
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

require("lazy").setup({
	{
		"artisanbk/hol4nvim",
		ft = "hol4script", -- lazy-load on *Script.sml buffers (see README)
		config = function()
			require("hol4nvim").setup({
				-- The one option worth setting -- and only when hol is not
				-- already discoverable (omit it if `hol` is on your $PATH):
				holdir = "~/GitScripts/HOL",

				-- Everything below is derived from holdir or defaulted.
				-- Uncomment only to override.

				-- hol_cmd = "~/GitScripts/HOL/bin/hol", -- a directory works too;
				--                          -- else <holdir>/bin/hol, lastmaker,
				--                          -- $HOLDIR/bin/hol, hol on $PATH
				-- fifo = "/some/fifo",     -- else $VIMHOL_FIFO, else
				--                          -- <holdir>/tools/editor-modes/vim/fifo
				-- vimhol = true,           -- REPL auto-bootstrap; false disables,
				--                          -- or a path to a specific vimhol.sml
				-- transport = "auto",      -- "terminal" | "fifo"
				-- split = "vertical",      -- "horizontal"
				-- start_insert = false,    -- focus the REPL in insert mode after \x
				-- keymaps = true,          -- false: no buffer-local keymaps
				-- prefix = "<localleader>",
				-- abbreviations = false,   -- holabs ASCII->unicode while typing
			})
		end,
	},
})
