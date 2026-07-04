--[[
  hol4nvim.keymaps -- the single registry of buffer-local HOL keymaps.

  ftplugin/hol4script.lua calls attach() for each hol4script buffer. One spec
  entry per map keeps the table aligned with upstream hol.vim's letters (see
  ROADMAP.md for the full reference); hw is kept as an alias of hs for
  upstream muscle memory (there it is the terminal-transport send; here the
  transports are unified behind send()).

  Config (repl.config): keymaps = false disables all of them; prefix
  overrides <localleader>.
--]]

local M = {}

local function specs()
	local repl = require("hol4nvim.repl")
	local select = require("hol4nvim.select")
	local search = require("hol4nvim.search")
	return {
		-- session
		{ "n", "x", repl.open, "Start REPL" },
		{ "n", "X", repl.close, "Close REPL" },
		-- send raw SML
		{ "n", "s", repl.send_line, "Send current line" },
		{ "x", "s", repl.send_visual, "Send selection" },
		{ "n", "w", repl.send_line, "Send current line (alias of s)" },
		{ "x", "w", repl.send_visual, "Send selection (alias of s)" },
		{ "n", "u", repl.send_quiet_line, "Send current line quietly" },
		{ "x", "u", repl.send_quiet_visual, "Send selection quietly" },
		{ "n", "!", repl.send_document, "Send whole document (opens dropped)" },
		{ "x", "!", repl.send_document, "Send whole document (opens dropped)" },
		-- proof transforms
		{ "n", "e", repl.send_expand_line, "Expand tactic (current line)" },
		{ "x", "e", repl.send_expand_visual, "Expand tactic (selection)" },
		{ "n", "g", repl.send_goal_line, "Set goal (current line)" },
		{ "x", "g", repl.send_goal_visual, "Set goal (selection)" },
		{ "n", "G", repl.send_uqgoal_line, "Set unquoted goal (current line)" },
		{ "x", "G", repl.send_uqgoal_visual, "Set unquoted goal (selection)" },
		{ "n", "S", repl.send_subgoal_line, "Subgoal (current line)" },
		{ "x", "S", repl.send_subgoal_visual, "Subgoal (selection)" },
		{ "n", "F", repl.send_suffices_line, "Suffices (current line)" },
		{ "x", "F", repl.send_suffices_visual, "Suffices (selection)" },
		{ "n", "P", repl.send_pattern_line, "Pattern goal (current line)" },
		{ "x", "P", repl.send_pattern_visual, "Pattern goal (selection)" },
		-- dependencies
		{ "n", "l", repl.send_load_line, "Load deps (current line)" },
		{ "x", "l", repl.send_load_visual, "Load deps (selection)" },
		-- proof-manager control (count repeats b/B/d; count is R's argument)
		{ "n", "b", repl.backup, "Back up proof step (count repeats)" },
		{ "n", "B", repl.restore, "Restore proof save point (count repeats)" },
		{ "n", "v", repl.save, "Save proof state" },
		{ "n", "d", repl.drop, "Drop current goal (count repeats)" },
		{ "n", "p", repl.p, "Print current proof state" },
		{ "n", "r", repl.restart, "Restart current goal" },
		{ "n", "R", repl.rotate, "Rotate subgoals (count)" },
		{ "n", "c", repl.interrupt, "Interrupt running tactic" },
		-- theorem database search (renders results in a scratch split)
		{ "n", "f", search.find, "Search theorems by name" },
		{ "n", "m", search.match, "Search theorems by term" },
		{ "x", "m", search.match_visual, "Search theorems by selected term" },
		-- selection helpers (no REPL: they make the selection to send)
		{ "n", "t", select.term, "Select `term`" },
		{ "n", "T", select.quoted_term, "Select ``term``" },
		{ "n", "a", select.theorem, "Select theorem statement + Proof" },
		-- display toggles
		{ "n", "y", repl.toggle_types, "Toggle Globals.show_types" },
		{ "n", "n", repl.toggle_unicode, "Toggle unicode printing" },
		-- upstream's `no <LocalLeader>h h`: with localleader h (the vimhol
		-- docs' convention), hh still moves left
		{ "n", "h", "h", "Pass h through" },
		{ "x", "h", "h", "Pass h through" },
		{ "o", "h", "h", "Pass h through" },
	}
end

--- The distinct suffix keys (the char after the prefix) across all maps.
--- health.lua uses these to know which `prefix..suffix` lhs's exist, so the
--- prefix/leader collision check stays in sync with the registry above.
M.suffixes = function()
	local seen, out = {}, {}
	for _, spec in ipairs(specs()) do
		local suffix = spec[2]
		if not seen[suffix] then
			seen[suffix] = true
			out[#out + 1] = suffix
		end
	end
	return out
end

--- Install the buffer-local keymaps for the current buffer.
M.attach = function()
	local config = require("hol4nvim.repl").config
	if config.keymaps == false then
		return
	end
	local prefix = config.prefix or "<localleader>"
	for _, spec in ipairs(specs()) do
		local mode, suffix, rhs, desc = spec[1], spec[2], spec[3], spec[4]
		vim.keymap.set(mode, prefix .. suffix, rhs, {
			buffer = true,
			silent = true,
			desc = "HOL4: " .. desc,
		})
	end
end

return M
