--[[
  This file is the pre-buffer setup for HOL4 script files
--]]

--[[
  Reload guard: if current buffer has already been set up, then exit.
  Avoids reapplying keymaps / options
--]]
if vim.b.did_ftplugin then
	return
end

vim.b.did_ftplugin = true
local repl = require("holnvim.repl")

--[[
  KEYMAPS FOR HOL4
--]]

if repl.config.keymaps ~= false then
	local prefix = repl.config.prefix or "<localleader>"
	local function map(mode, lhs, rhs, desc)
		vim.keymap.set(mode, prefix .. lhs, rhs, {
			buffer = true,
			silent = true,
			desc = desc,
		})
	end
	map("n", "x", repl.open, "HOL4: Start REPL")
	map("n", "X", repl.close, "HOL4: Close REPL")
	map("n", "s", repl.send_line, "HOL4: Send current line")
	map("x", "s", repl.send_visual, "HOL4: Send selection")
	map("n", "e", repl.send_expand_line, "HOL4: Expand tactic (current line)")
	map("x", "e", repl.send_expand_visual, "HOL4: Expand tactic (selection)")
	map("n", "l", repl.send_load_line, "HOL4: Load deps (current line)")
	map("x", "l", repl.send_load_visual, "HOL4: Load deps (selection)")
end
