--[[
  This file drives a HOL4 interactive session in neovim :terminal buffer.
  This is a port of HOL's tools/editor-modes/vim/hol.vim
  The entry point is M.open()
--]]

local M = {}

-- Config which can be overwritten at `init.lua` setup()
M.config = {
	hol_cmd = nil, -- explicit path / command to run
	split = "vertical",
	start_insert = false, -- enter vim insert mode after opening
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
	for job_id, session in ipairs(M.sessions) do
		if session.job == remove_job then
			if session.pipe then
				pcall(vim.uv.fs_unlink, session.pipe)
			end
			table.remove(M.sessions, job_id)
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
  Send raw text to current session (no ";\n" appended) via chansend() into
  the STDIN end of that channel; We use send_line() for the additional ";\n"
  This is a port of `HOLREPLsend`;
--]]
M.send = function(text)
	local s = M.current()
	if not s then
		vim.notify(
			"holnvim: no active hol repl (open one with :HolStart)",
			vim.log.levels.WARN
		)
		return
	end
	vim.fn.chansend(s.job, text)
end

--[[
  line / selection helpers (appends ";\n")
--]]
M.send_line = function()
	M.send(vim.api.nvim_get_current_line() .. ";\n")
end

--[[
  There is no robust way to get selected visual mode text from vim;
  The solve is to copy in into the unnamed register `"` and read it from there;
--]]
M.send_visual = function()
	local save_reg = vim.fn.getreg('"')
	local save_type = vim.fn.getregtype('"')
	vim.cmd("noautocmd silent normal! gvy")
	local text = vim.fn.getreg('"')
	vim.fn.setreg('"', save_reg, save_type)
	M.send(text .. ";\n")
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
