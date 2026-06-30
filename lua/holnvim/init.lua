--[[
  Public entry point;
  Responsibilities:
  - setup(opts) : fold user options into the repl config
  - Define the HOL user commands
  (Filetype detection lives in ftdetect/hol4script.lua.)
--]]

local repl = require("holnvim.repl")
local M = {}

local function create_commands()
	vim.api.nvim_create_user_command("HolStart", function()
		repl.open()
	end, { desc = "Starts a HOL4 REPL beside current file." })

	vim.api.nvim_create_user_command("HolStop", function()
		repl.close()
	end, { desc = "Close current HOL4 REPL." })

	vim.api.nvim_create_user_command("HolSend", function(cmd)
		if cmd.range > 0 then
			repl.send_visual()
		else
			repl.send_line()
		end
	end, { range = true, desc = "Send current line / selection to HOL4 REPL" })
end

--[[
  Entry points; Call once from config via `require("holnvim").setup({...})`
--]]
M.setup = function(opts)
	opts = opts or {}
	repl.config = vim.tbl_deep_extend("force", repl.config, opts)
	create_commands()
end

return M
