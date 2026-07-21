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

	vim.api.nvim_create_user_command("HolExternalSetup", function(cmd)
		local target = cmd.args ~= "" and cmd.args or nil
		local res, reason = repl.write_shell_rc(target)
		if not res then
			vim.notify(
				"hol4nvim: external setup unavailable -- " .. reason,
				vim.log.levels.ERROR
			)
			return
		end
		vim.notify(
			table.concat({
				"hol4nvim: " .. res.action .. " a managed block in " .. res.path .. ".",
				"Start (or restart) hol in your terminal -- or `source` that file --",
				"and any hol you launch attaches Vimhol to the fifo. It sets:",
				"",
				"  HOL_CONFIG  = " .. res.env.HOL_CONFIG,
				"  VIMHOL_FIFO = " .. res.env.VIMHOL_FIFO,
				"",
				"No ~/.hol-config.sml is created; the loader lives in Neovim's data",
				"dir and runs your own hol-config first (if any). Delete the marked",
				"block to undo.",
			}, "\n"),
			vim.log.levels.INFO
		)
	end, {
		nargs = "?",
		complete = "file",
		desc = "Write a managed HOL_CONFIG/VIMHOL_FIFO block to your shell rc (optional: target file)",
	})
end

--[[
  Entry points; Call once from config via `require("hol4nvim").setup({...})`
--]]
M.setup = function(opts)
	opts = opts or {}
	-- Specs routinely say "~/..." -- but jobstart/filereadable/writefile take
	-- `~` literally, so expand path-like options once here. `vimhol` is only
	-- path-like in its explicit-path form (true/false pass through).
	for _, key in ipairs({ "hol_cmd", "holdir", "fifo", "vimhol", "shell_rc" }) do
		if type(opts[key]) == "string" and opts[key] ~= "" then
			opts[key] = vim.fs.normalize(opts[key])
		end
	end
	repl.config = vim.tbl_deep_extend("force", repl.config, opts)
	create_commands()

	-- Keep the external-session loader current (picked up when $HOL_CONFIG
	-- points at it; see :HolExternalSetup). Silent and non-fatal: a HOL-free
	-- install where vimhol.sml can't be resolved simply skips it.
	pcall(repl.write_hol_config)

	-- opt-in: also keep the managed shell-rc block current, so an external hol
	-- works without remembering :HolExternalSetup. Off by default -- writing to
	-- a user's rc is only ever done on an explicit request, whether that is the
	-- command or this flag. Idempotent, so re-running on every setup() is a
	-- no-op once the block is correct.
	if repl.config.auto_shell_rc then
		pcall(repl.write_shell_rc)
	end

	-- Insert-mode completion (tactics + live theorem names). Its own config
	-- block; setup() registers the nvim-cmp source and the refresh autocmds.
	local completion = require("hol4nvim.completion")
	if type(opts.completion) == "table" then
		completion.config = vim.tbl_deep_extend("force", completion.config, opts.completion)
	end
	completion.setup()
end

return M
