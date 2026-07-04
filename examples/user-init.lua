--[[
  Example user config for hol4nvim -- copy into ~/.config/nvim/init.lua, or
  merge the plugin spec into your existing lazy.nvim plugin list.

  The plugin derives everything from one root. If `hol` is already
  discoverable -- on $PATH, via a .HOLMK/lastmaker next to your script, or
  through an exported $HOLDIR -- the setup({}) needs NO options at all.
  Otherwise set `holdir` and stop: the hol binary (<holdir>/bin/hol),
  holdeptool for hl, the default fifo path, and vimhol.sml for the REPL
  auto-bootstrap are all found from it. Paths may use "~".
--]]

return {
	"artisanbk/hol4nvim",
	ft = "hol4script", -- lazy-load on *Script.sml buffers (see README)
	build = "make parsers", -- compile the tree-sitter syntax tier (needs cc;
	-- optional: without it the regex tier loads instead)
	dependencies = { "hrsh7th/nvim-cmp" }, -- optional: insert-mode completion
	config = function()
		require("hol4nvim").setup({
			-- The one option worth setting -- and only when hol is not
			-- already discoverable (omit it if `hol` is on your $PATH):
			holdir = "~/SomePath/HOL",

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
			-- start_insert = false,    -- focus the REPL in insert mode after hx
			-- keymaps = true,          -- false: no buffer-local keymaps
			-- prefix = "<localleader>",
			-- abbreviations = false,   -- holabs ASCII->unicode while typing
			-- completion = {           -- insert-mode completion (needs nvim-cmp)
			--   enabled = true,        -- :HolCompletionToggle at runtime
			--   auto_setup = true,     -- add the source to hol4script's cmp
			--   tactics = true,        -- static HOL tactic vocabulary
			--   theorems = true,       -- live theorem names from the session
			-- },
		})
	end,
}
