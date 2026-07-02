--[[
  This file drives a HOL4 interactive session in neovim :terminal buffer.
  This is a port of HOL's tools/editor-modes/vim/hol.vim
  The entry point is M.open()
--]]

local M = {}

-- Reshape selections into proof-manager calls (the "what to send" layer).
local transform = require("holnvim.transform")

-- Config which can be overwritten at `init.lua` setup()
M.config = {
	hol_cmd = nil, -- explicit path / command to run
	split = "vertical",
	start_insert = false, -- enter vim insert mode after opening
	transport = "auto", -- "auto" | "terminal" | "fifo": how send() delivers
	fifo = nil, -- explicit fifo path; else $VIMHOL_FIFO, else $HOLDIR default
	abbreviations = false, -- ASCII->unicode insert abbreviations (holabs)
}

-- Stack of { buf = <bufnr>, job = <chan id>, pipe = <fifo path> }.
M.sessions = {}

--- The current (top-of-stack) session, or nil if none is live.
M.current = function()
	return M.sessions[#M.sessions]
end

--[[
  Port of LastmakerHOL. If Holmake was run in the theory file's
  directory, .HOLMK/lastmaker records the Holmake binary used; the matching
  `hol` sits beside it, so rewrite Holmake -> hol to pick the same build.
  (Upstream resolves .HOLMK relative to cwd; we resolve relative to the edited
  file's directory, which is the documented intent and the REPL's spawn cwd.)
--]]
local function lastmaker_hol()
	local dir = vim.fn.expand("%:p:h")
	local lastmaker = dir .. "/.HOLMK/lastmaker"
	if vim.fn.filereadable(lastmaker) == 1 then
		local lines = vim.fn.readfile(lastmaker, "", 1)
		if #lines > 0 and lines[1] ~= "" then
			return vim.fn.fnamemodify(lines[1], ":s?Holmake?hol?")
		end
	end
	return ""
end

-- find HOL4 executable
M.which_hol = function()
	if M.config.hol_cmd and M.config.hol_cmd ~= "" then
		-- not nil (overwritten in init config) and not empty
		return M.config.hol_cmd
	end

	local lm = lastmaker_hol()
	if vim.fn.executable(lm) == 1 then
		return lm
	end

	local holdir = vim.env.HOLDIR
	if holdir and holdir ~= "" then
		local hol = holdir .. "/bin/hol"
		if vim.fn.executable(hol) == 1 then
			return hol
		end
	end

	if vim.fn.executable("hol") == 1 then
		return "hol"
	end

	return ""
end

--[[
  For removing session(s) from stack and clean up the fifo.
  This is used by `on_exit` so a REPL that dies or
  is closed from its own shell doesn't leave a stale
  entry that `send()` can try to write to.
--]]
local function prune(remove_job)
	for idx, session in ipairs(M.sessions) do
		if session.job == remove_job then
			if session.pipe then
				pcall(vim.uv.fs_unlink, session.pipe)
			end
			table.remove(M.sessions, idx)
			return
		end
	end
end

-- Spawn a hol session in a split, push session
-- Port of HOLREPLnew()
M.open = function()
	--[[
    Spawn hol process and record a handle to it;
    Exit if spawn process fails
  --]]
	local cmd = M.which_hol()
	if cmd == "" or vim.fn.executable(cmd) ~= 1 then
		vim.notify("hol_nvim: hol command not found (" .. cmd .. ").\
      Set $HOLDIR or config.hol_cmd", vim.log.levels.ERROR)
		return
	end

	--[[
    Per session snapshots of current active cmd names
  --]]
	local src_win = vim.api.nvim_get_current_win()
	local cwd = vim.fn.expand("%:p:h")
	local altname = vim.fn.expand("%:t:r")

	--[[
    Create per session fifo; This will be used by `he` and `hs` commands;
  --]]
	local pipe = vim.fn.tempname()
	vim.system({ "mkfifo", pipe }):wait()

	--[[
    Make window and empty buffer;
    Also checks if there is a user preference for "horizontal"
  --]]
	vim.cmd(
		(M.config.split == "horizontal" and "split" or "vsplit") .. " | enew"
	)

	--[[
    Spawn process as a terminal;
    Turns current buffer into terminal and run `cmd`;
  --]]
	local job = vim.fn.jobstart(cmd, {
		cwd = cwd,
		term = true,
		env = { VIMHOL_FIFO = pipe }, -- extends the inherited environment
		on_exit = function(j)
			prune(j)
		end,
	})

	--[[
    Spawn cleaning;
    Removes any windows during a crash or exit;
  --]]
	if job <= 0 then
		vim.notify(
			"holnvim: failed to start hol (" .. cmd .. ")",
			vim.log.levels.ERROR
		)
		pcall(vim.uv.fs_unlink, pipe)
		vim.cmd("bwipeout!") -- discard the empty terminal window
		return
	end

	--[[
    Record current session;
  --]]
	local buf = vim.api.nvim_get_current_buf()
	table.insert(M.sessions, { buf = buf, job = job, pipe = pipe })

	--[[
    Assign unique, informative buffer name: "hol (<bufnr>): <FooScript>".
  --]]
	pcall(vim.api.nvim_buf_set_name, buf, "hol (" .. buf .. "): " .. altname)

	vim.cmd("normal! G") -- scroll to the bottom of the REPL output

	if M.config.start_insert then -- restore focus
		vim.cmd("startinsert")
	else
		if vim.api.nvim_win_is_valid(src_win) then
			vim.api.nvim_set_current_win(src_win)
		end
	end
end

--[[
  Terminal transport. Single lines go into the session's pty via chansend()
  ("\n" is the Enter that submits; the ";" terminator is already appended).
  Port of HOLREPLsend's nvim branch (hol.vim:337).

  Multi-line batches instead go through the session's OWN Vimhol pipe when a
  reader is attached (repl.open exports VIMHOL_FIFO; a hol-config that use's
  vimhol.sml tails it): hol then QUse.use's a temp Script file, giving real
  script-file parsing. Fed raw into the pty, a batch glues statements that
  lack ";" and can wedge hol's filter at its '#' prompt mid-construct.
  Without a Vimhol reader we fall back to the pty and hope for the best.
--]]
local function terminal_send(session, text)
	if text:find("\n") and session.pipe then
		local fifo = require("holnvim.fifo")
		if fifo.ready(session.pipe) then
			fifo.send(text, session.pipe)
			return
		end
	end
	vim.fn.chansend(session.job, text .. "\n")
end

--[[
  Guard against wedging the REPL: a script-file block construct (Theorem,
  Definition, ...) sent without its closing keyword leaves hol's filter
  waiting on the `#` continuation prompt, and the NEXT send gets eaten as
  continuation of the broken construct (Ctrl-C in the terminal recovers).
  Typical cause: a charwise visual selection stopping short of the closer.
  Returns the missing closer's keyword, or nil if the text looks complete.
--]]
local blocks = {
	{ opener = "^Theorem%f[%A]", closer = "^QED%f[%W]", name = "QED" },
	{ opener = "^Triviality%f[%A]", closer = "^QED%f[%W]", name = "QED" },
	{ opener = "^Definition%f[%A]", closer = "^End%f[%W]", name = "End" },
	{ opener = "^Datatype%f[%A]", closer = "^End%f[%W]", name = "End" },
	{ opener = "^Inductive%f[%A]", closer = "^End%f[%W]", name = "End" },
	{ opener = "^CoInductive%f[%A]", closer = "^End%f[%W]", name = "End" },
}

local function missing_closer(text)
	local pending = nil
	for line in (text .. "\n"):gmatch("(.-)\n") do
		if pending then
			if line:find(pending.closer) then
				pending = nil
			end
		else
			for _, block in ipairs(blocks) do
				if line:find(block.opener) then
					pending = block
					break
				end
			end
		end
	end
	return pending and pending.name
end

M.send = function(text)
	local missing = missing_closer(text)
	if missing then
		-- a last line like "Q" or "QE" means a charwise (v) selection swept
		-- onto the closer's line but stopped short of its end
		local last = text:gsub("[;%s]*$", ""):match("([^\n]*)$") or ""
		local hint = ""
		if #last > 0 and #last < #missing and missing:sub(1, #last) == last then
			hint = " The selection ends with '"
				.. last
				.. "' -- a charwise (v) selection stopped short of the full '"
				.. missing
				.. "'."
		end
		vim.notify(
			"holnvim: not sent -- incomplete block, no closing '"
				.. missing
				.. "' in the selection."
				.. hint
				.. " (Sending it would wedge the REPL at its '#' prompt;"
				.. " select the whole block linewise with V.)",
			vim.log.levels.WARN
		)
		return
	end

	local mode = M.config.transport or "auto"
	local session = M.current()
	if mode ~= "fifo" and session then
		-- terminal transport (in-vim REPL)
		terminal_send(session, text)
	elseif mode ~= "terminal" then
		-- fifo transport (external HOL tailing the pipe). Lazy-require breaks
		-- the load-time cycle between repl and fifo.
		local fifo = require("holnvim.fifo")
		if fifo.ready() then
			fifo.send(text)
		else
			vim.notify(
				"holnvim: no in-vim REPL and no fifo reader\
        (start one with the open keymap, or launch a Vimhol HOL session)",
				vim.log.levels.WARN
			)
		end
	else
		vim.notify(
			"holnvim: transport=terminal but no in-VIM REPL",
			vim.log.levels.WARN
		)
	end
end

--[[
  Text gatherers. current_line() / visual_selection() collect buffer text.

  The keymaps invoke visual_selection() while visual mode is still ACTIVE
  (Lua callbacks, unlike upstream's ":call" maps, do not leave visual mode
  first), so the live selection must be read with getregion() -- a gv-based
  reselect would grab the PREVIOUS selection's stale marks and send garbage.
  The register fallback stays for mark-based flows (e.g. :'<,'>HolSend).
--]]
local function current_line()
	return vim.api.nvim_get_current_line()
end

local function visual_selection()
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		local lines =
			vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
		-- leave visual mode synchronously (sets '< '>), as upstream's
		-- ":call" maps do implicitly
		vim.cmd("normal! \27")
		return table.concat(lines, "\n")
	end

	-- not in visual mode: reselect the last selection via the unnamed
	-- register (saving/restoring it)
	local save_reg = vim.fn.getreg('"')
	local save_type = vim.fn.getregtype('"')
	vim.cmd("noautocmd silent normal! gvy")
	local text = vim.fn.getreg('"')
	vim.fn.setreg('"', save_reg, save_type)
	return (text:gsub("\n$", "")) -- linewise yank: drop the trailing newline
end

--[[
  Senders. Each collects text, optionally reshapes it via a transform, appends
  the ";" terminator, and routes through send(). The ";" is required by the
  terminal transport (to submit the statement) and harmless for the fifo one.
    s -> raw SML            e -> apply selection as a tactic (expand)
    g -> set goal           S -> subgoal
    F -> suffices           P -> pattern goal
--]]
-- Shared by all senders: strip comments, refusing text whose comments never
-- close (an unclosed '(*' swallows everything after it -- including a QED --
-- both here and in hol's own nesting lexer). Returns nil when refused.
local function stripped_or_warn(raw)
	local text, unclosed = transform.strip_comments(raw)
	if unclosed then
		vim.notify(
			"holnvim: not sent -- unclosed comment: a '(*' on line "
				.. unclosed
				.. " of the selection has no matching '*)'. SML comments"
				.. " nest, so every '(*' inside a comment needs its own '*)'.",
			vim.log.levels.WARN
		)
		return nil
	end
	if not text:find("%S") then
		vim.notify(
			"holnvim: nothing to send (only comments/whitespace)",
			vim.log.levels.INFO
		)
		return nil
	end
	return text
end

local function senders(reshape)
	local function sender(gather)
		return function()
			local text = stripped_or_warn(gather())
			if not text then
				return
			end
			M.send((reshape and reshape(text) or text) .. ";")
		end
	end
	return sender(current_line), sender(visual_selection)
end

--[[
  send_document: send the entire buffer as one batch (no upstream
  equivalent; mapped to \! and :HolSendDocument). `open` declarations are
  dropped: in an interactive session, `open` of a theory that is not loaded
  yet fails -- use the load keymap (\l) over the open lines first instead.
  An `open` may span lines; it is taken to continue over nonblank lines of
  bare identifiers, ending at one that carries a ";".
--]]
local function without_opens(lines)
	local kept, i = {}, 1
	while i <= #lines do
		local line = lines[i]
		if line:find("^%s*open%f[%W]") then
			local ended = line:find(";") ~= nil
			i = i + 1
			while not ended and i <= #lines do
				local cont = lines[i]
				if cont:find("%S") and cont:find("^[%s%w_.;']*$") then
					ended = cont:find(";") ~= nil
					i = i + 1
				else
					ended = true
				end
			end
		else
			kept[#kept + 1] = line
			i = i + 1
		end
	end
	return kept
end

M.send_document = function()
	if vim.fn.mode():match("[vV\22]") then
		vim.cmd("normal! \27") -- \! pressed from visual mode: leave it
	end
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local text = stripped_or_warn(table.concat(without_opens(lines), "\n"))
	if not text then
		return
	end
	M.send(text .. ";")
end

M.send_line, M.send_visual = senders(nil)
M.send_quiet_line, M.send_quiet_visual = senders(transform.quiet)
M.send_expand_line, M.send_expand_visual = senders(transform.expand)
M.send_goal_line, M.send_goal_visual = senders(transform.goal)
M.send_uqgoal_line, M.send_uqgoal_visual = senders(transform.uqgoal)
M.send_subgoal_line, M.send_subgoal_visual = senders(transform.subgoal)
M.send_suffices_line, M.send_suffices_visual = senders(transform.suffices)
M.send_pattern_line, M.send_pattern_visual = senders(transform.pattern)

--[[
  load: process `load`s for a selected script header (port of HOLLoad,
  hol.vim:59-83). Runs holdeptool over the selection to discover the theory
  dependencies, then sends `val _ = load"..."` for each, so those modules are
  available in the session -- after which `open`s and goals on them work.
--]]

-- Resolve holdeptool.exe: next to the chosen hol, else under $HOLDIR/bin.
local function holdeptool()
	local hol = M.which_hol()
	if hol ~= "" then
		local tool = vim.fn.fnamemodify(hol, ":h") .. "/holdeptool.exe"
		if vim.fn.executable(tool) == 1 then
			return tool
		end
	end
	local holdir = vim.env.HOLDIR
	if holdir and holdir ~= "" then
		local tool = holdir .. "/bin/holdeptool.exe"
		if vim.fn.executable(tool) == 1 then
			return tool
		end
	end
	return ""
end

local function send_load(text)
	text = stripped_or_warn(text)
	if not text then
		return
	end

	local tool = holdeptool()
	if tool == "" then
		vim.notify(
			"holnvim: holdeptool.exe not found (set $HOLDIR)",
			vim.log.levels.ERROR
		)
		return
	end

	-- holdeptool analyses a file, so write the selected header to a temp file.
	local tmp = vim.fn.tempname()
	vim.fn.writefile(vim.split(text, "\n", { plain = true }), tmp)

	-- One dependency per output line -> one load statement each.
	local deps = vim.fn.systemlist({ tool, tmp })
	if vim.v.shell_error ~= 0 then
		vim.notify(
			"holnvim: holdeptool failed:\n" .. table.concat(deps, "\n"),
			vim.log.levels.ERROR
		)
		return
	end

	local loads, names = {}, {}
	for _, dep in ipairs(deps) do
		if dep ~= "" then
			table.insert(loads, 'val _ = load"' .. dep .. '";')
			table.insert(names, dep)
		end
	end
	if #loads == 0 then
		vim.notify("holnvim: no dependencies to load", vim.log.levels.INFO)
		return
	end

	--[[
	  Full HOLLoad shape (hol.vim:69-83): the loads, then the SELECTION
	  ITSELF executed inside quietdec toggles (so an `open`'s binding dump
	  is suppressed), then a "...completed" confirmation print.
	--]]
	M.send(table.concat({
		table.concat(loads, " "),
		transform.quiet(text) .. ";",
		'val _ = print "HOLLoad '
			.. table.concat(names, " ")
			.. ' completed\\n";',
	}, "\n"))
end

M.send_load_line = function()
	send_load(current_line())
end

M.send_load_visual = function()
	send_load(visual_selection())
end

--[[
  Proof-manager control commands (port of hol.vim:195-273). Thin literal
  proofManagerLib calls through send(). `count` defaults to the keymap's
  v:count1: it REPEATS backup/restore/drop (upstream HOLRepeat -- 3\b backs
  up three steps) and is rotate's argument (upstream HOLRotate).
--]]
local function repeated(stmt)
	return function(count)
		local n = count or vim.v.count1
		local parts = {}
		for _ = 1, n do
			parts[#parts + 1] = stmt
		end
		M.send(table.concat(parts, " "))
	end
end

M.backup = repeated("proofManagerLib.backup();")
M.restore = repeated("proofManagerLib.restore();")
M.drop = repeated("proofManagerLib.drop();")

M.save = function()
	M.send("proofManagerLib.save();")
end

M.p = function()
	M.send("proofManagerLib.p();")
end

M.restart = function()
	M.send("proofManagerLib.restart();")
end

M.rotate = function(count)
	M.send("proofManagerLib.rotate(" .. (count or vim.v.count1) .. ");")
end

--[[
  Display toggles (port of the \y and \n mappings, hol.vim:272-273).
--]]
M.toggle_types = function()
	M.send("Globals.show_types := not (!Globals.show_types);")
end

M.toggle_unicode = function()
	M.send(
		'Feedback.set_trace "PP.avoid_unicode"'
			.. ' (1 - Feedback.current_trace "PP.avoid_unicode");'
	)
end

--[[
  Interrupt the running tactic (port of HOLINT, hol.vim:207-211). Vimhol's
  poller reacts to a literal "Interrupt" line on the fifo by interrupting
  its proof thread -- this cannot go through send(), which would only queue
  more input behind the busy evaluator. Priority: the session's own pipe,
  then the global fifo (external session), then CTRL-C into the pty (the
  line discipline turns it into SIGINT, which PolyML takes as Interrupt).
--]]
M.interrupt = function()
	local fifo = require("holnvim.fifo")
	local session = M.current()
	if session and session.pipe and fifo.ready(session.pipe) then
		vim.fn.writefile({ "Interrupt" }, session.pipe, "a")
		return
	end
	if fifo.ready() then
		vim.fn.writefile({ "Interrupt" }, fifo.path(), "a")
		return
	end
	if session then
		vim.fn.chansend(session.job, "\3") -- CTRL-C
		return
	end
	vim.notify("holnvim: no HOL session to interrupt", vim.log.levels.WARN)
end

--[[
  Ctrl + D hol session and pop stack
--]]
M.close = function()
	local s = M.current()
	if not s then
		return
	end
	vim.fn.chansend(s.job, "\4") -- CTRL+D
end

return M
