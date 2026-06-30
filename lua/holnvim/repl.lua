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
  Terminal transport: write the statement into the session's pty via
  chansend(). Appends "\n" -- the Enter keypress that submits the line. The ";"
  statement terminator is already added by the gatherers below.
  Port of HOLREPLsend's nvim branch (hol.vim:337).
--]]
local function terminal_send(session, text)
	vim.fn.chansend(session.job, text .. "\n")
end

M.send = function(text)
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
  There is no robust direct call for the visual selection, so we yank it into
  the unnamed register `"` (saving/restoring it) and read it back.
--]]
local function current_line()
	return vim.api.nvim_get_current_line()
end

local function visual_selection()
	local save_reg = vim.fn.getreg('"')
	local save_type = vim.fn.getregtype('"')
	vim.cmd("noautocmd silent normal! gvy")
	local text = vim.fn.getreg('"')
	vim.fn.setreg('"', save_reg, save_type)
	return text
end

--[[
  Senders. Each collects text, optionally reshapes it via a transform, appends
  the ";" terminator, and routes through send(). The ";" is required by the
  terminal transport (to submit the statement) and harmless for the fifo one.
    s -> raw SML            e -> apply selection as a tactic (expand)
--]]
M.send_line = function()
	M.send(current_line() .. ";")
end

M.send_visual = function()
	M.send(visual_selection() .. ";")
end

M.send_expand_line = function()
	M.send(transform.expand(current_line()) .. ";")
end

M.send_expand_visual = function()
	M.send(transform.expand(visual_selection()) .. ";")
end

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

	local loads = {}
	for _, dep in ipairs(deps) do
		if dep ~= "" then
			table.insert(loads, 'val _ = load"' .. dep .. '";')
		end
	end
	if #loads == 0 then
		vim.notify("holnvim: no dependencies to load", vim.log.levels.INFO)
		return
	end

	M.send(table.concat(loads, "\n"))
end

M.send_load_line = function()
	send_load(current_line())
end

M.send_load_visual = function()
	send_load(visual_selection())
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
