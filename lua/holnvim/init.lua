--[[
  Public entry point;
  Responsibilities:
  - setup(opts) : fold user options into the repl config
  - Define the HOL user commands
  - Register filetype detection: so that HOL script files load ftplugin
--]]

local repl = require("holnvim.repl")
local M = {}

--[[
  Map "*Script.sml" onto the `hol4script` filetype.
  Neovim should run ftplugin/hol4script.lua (buffer setup + keymaps)
  and apply syntax matching automatically;
--]]
local function register_filetype()
	vim.filetype.add({
		pattern = {
			[".*Script%.sml"] = "hol4script",
		},
	})
end

local function create_commands()
	vim.api.nvim_create_user_coammand("HolStart", function()
		repl.open()
	end, { desc = "Starts a HOL4 REPL beside current file." })

	vim.api.nvim_create_user_coammand("HolStop", function()
		repl.close()
	end, { desc = "Close current HOL4 REPL." })

	vim.api.nvim_create_user_coammand("HolSend", function(cmd)
		if cmd.range > 0 then
			repl.send_visual()
		else
			repl.send_line()
		end
	end, { desc = "Send current line / selection to HOL4 REPL" })
end

--[[
  Entry points; Call once from config via `require("holnvim").setup({...})`
--]]
M.setup = function(opts)
	opts = opts or {}
	repl.config = vim.tbl_deep_extend("force", repl.config, opts)
	register_filetype()
	create_commands()
end

return M
