--[[
  Public entry point;
  Responsibilities:
  - setup(opts) : fold user options into the repl config
  - Define the HOL user commands
  (Filetype detection lives in ftdetect/hol4script.lua.)
--]]

local repl = require("hol4nvim.repl")
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

	vim.api.nvim_create_user_command("HolSendDocument", function()
		repl.send_document()
	end, { desc = "Send whole buffer to HOL4 REPL (open lines dropped)" })

	vim.api.nvim_create_user_command("HolUnabbrev", function(cmd)
		require("hol4nvim.abbrev").unabbrev(cmd.line1, cmd.line2)
	end, {
		range = "%",
		desc = "Replace HOL unicode with ASCII (whole buffer, or a range)",
	})

	vim.api.nvim_create_user_command("HolFind", function(cmd)
		local search = require("hol4nvim.search")
		if cmd.args ~= "" then
			search.run("name", cmd.args)
		else
			search.find()
		end
	end, { nargs = "?", desc = "Search HOL theorems by name (DB.find)" })

	vim.api.nvim_create_user_command("HolMatch", function(cmd)
		local search = require("hol4nvim.search")
		if cmd.args ~= "" then
			search.run("term", cmd.args)
		else
			search.match()
		end
	end, { nargs = "?", desc = "Search HOL theorems by term (DB.apropos)" })

	vim.api.nvim_create_user_command("HolCompletionRefresh", function()
		require("hol4nvim.completion").refresh(function(ok, info)
			if ok then
				vim.notify(
					"hol4nvim: completion cache refreshed (" .. info .. " theorems)",
					vim.log.levels.INFO
				)
			else
				vim.notify(
					"hol4nvim: completion refresh failed -- " .. tostring(info),
					vim.log.levels.WARN
				)
			end
		end)
	end, { desc = "Refresh HOL theorem-name completion from the live session" })

	vim.api.nvim_create_user_command("HolCompletionToggle", function()
		require("hol4nvim.completion").toggle()
	end, { desc = "Toggle HOL insert-mode completion on/off" })
end

--[[
  Entry points; Call once from config via `require("hol4nvim").setup({...})`
--]]
M.setup = function(opts)
	opts = opts or {}
	-- Specs routinely say "~/..." -- but jobstart/filereadable/writefile take
	-- `~` literally, so expand path-like options once here. `vimhol` is only
	-- path-like in its explicit-path form (true/false pass through).
	for _, key in ipairs({ "hol_cmd", "holdir", "fifo", "vimhol" }) do
		if type(opts[key]) == "string" and opts[key] ~= "" then
			opts[key] = vim.fs.normalize(opts[key])
		end
	end
	repl.config = vim.tbl_deep_extend("force", repl.config, opts)
	create_commands()

	-- Insert-mode completion (tactics + live theorem names). Its own config
	-- block; setup() registers the nvim-cmp source and the refresh autocmds.
	local completion = require("hol4nvim.completion")
	if type(opts.completion) == "table" then
		completion.config = vim.tbl_deep_extend("force", completion.config, opts.completion)
	end
	completion.setup()
end

return M
