--[[
  holnvim.fifo -- fifo transport for send().

  The classic Vimhol delivery path: write the code to a temp *Script.sml file,
  then append "ReadFile <file>" to a named pipe. A HOL session running Vimhol
  (vimhol.sml) tails that pipe, use's the file, and deletes it. This reaches a
  HOL process started anywhere (e.g. your own terminal/tmux), not just an
  in-vim :terminal. Mirrors HOLCEnd / HOLCRestore (hol.vim:45-57).

  This module never requires holnvim.repl at load time -- only lazily inside
  functions -- so repl <-> fifo stays free of a load-time cycle.
--]]

local M = {}

-- open(2) flags. O_WRONLY is 1 everywhere; O_NONBLOCK is platform-specific.
local O_WRONLY = 1
local function o_nonblock()
	-- Darwin/BSD use 0x0004; Linux uses 0o4000 (0x0800). Default to Linux.
	if vim.uv.os_uname().sysname == "Darwin" then
		return 0x0004
	end
	return 0x0800
end

--[[
  Resolve the fifo path, in priority order:
    1. config.fifo (explicit override)
    2. $VIMHOL_FIFO (shared with the HOL session's environment)
    3. $HOLDIR/tools/editor-modes/vim/fifo (upstream default)
  Returns nil if none is determinable.
--]]
M.path = function()
	local cfg = require("holnvim.repl").config
	if cfg.fifo and cfg.fifo ~= "" then
		return cfg.fifo
	end

	local env = vim.env.VIMHOL_FIFO
	if env and env ~= "" then
		return env
	end

	local holdir = vim.env.HOLDIR
	if holdir and holdir ~= "" then
		return holdir .. "/tools/editor-modes/vim/fifo"
	end

	return nil
end

--[[
  True only if the pipe exists AND a reader is attached. We probe with a
  non-blocking write-open: with a reader the open succeeds; with no reader it
  fails immediately (ENXIO) instead of blocking. This is the safety check that
  stops an auto-routed send() from freezing Neovim on a readerless pipe.

  Opening and closing a write end is exactly what every real send does, so a
  Vimhol tail reader handles the probe the same way it handles a normal write.
--]]
M.ready = function()
	local path = M.path()
	if not path then
		return false
	end

	local flags = bit.bor(O_WRONLY, o_nonblock())
	local fd = vim.uv.fs_open(path, flags, 420) -- 420 = 0644 (ignored for a fifo)
	if fd then
		vim.uv.fs_close(fd)
		return true
	end
	-- nil fd: ENXIO (no reader), ENOENT (no pipe), etc. -- all "not ready".
	return false
end

--[[
  Deliver a ";"-terminated statement to the HOL session. Writes it to a temp
  file, then pokes the pipe with the file's name for Vimhol to use.
--]]
M.send = function(text)
	local path = M.path()
	if not path then
		vim.notify(
			"holnvim: no fifo path (set config.fifo, $VIMHOL_FIFO, or $HOLDIR)",
			vim.log.levels.ERROR
		)
		return
	end

	-- Temp file Vimhol will use then delete. The *Script.sml suffix matches
	-- upstream so HOL applies script-file parsing.
	local tmp = vim.fn.tempname() .. "Script.sml"
	vim.fn.writefile(vim.split(text, "\n", { plain = true }), tmp)

	-- Append the command line to the pipe. ready() confirmed a reader, so this
	-- write-open won't block (tiny TOCTOU window if the reader dies between).
	vim.fn.writefile({ "ReadFile " .. tmp }, path, "a")
end

return M
