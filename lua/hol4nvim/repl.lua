--[[
  This file drives a HOL4 interactive session in neovim :terminal buffer.
  This is a port of HOL's tools/editor-modes/vim/hol.vim
  The entry point is M.open()
--]]

local M = {}

-- Reshape selections into proof-manager calls (the "what to send" layer).
local transform = require("hol4nvim.transform")

-- Config which can be overwritten at `init.lua` setup()
M.config = {
	hol_cmd = nil, -- explicit path / command to run
	split = "vertical",
	start_insert = false, -- enter vim insert mode after opening
	transport = "auto", -- "auto" | "terminal" | "fifo": how send() delivers
	fifo = nil, -- explicit fifo path; else $VIMHOL_FIFO, else the holdir default
	holdir = nil, -- HOL root; else derived from the hol binary, else $HOLDIR
	vimhol = true, -- auto-load vimhol.sml into spawned REPLs; false | "/path"
	abbreviations = false, -- ASCII->unicode insert abbreviations (holabs)
	shell_rc = nil, -- rc file :HolExternalSetup writes to; else derived from $SHELL
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
		local cmd = M.config.hol_cmd
		if vim.fn.isdirectory(cmd) == 1 then
			-- tolerate a directory (the bin/ dir, or the HOL root itself)
			for _, suffix in ipairs({ "/hol", "/bin/hol" }) do
				if vim.fn.executable(cmd .. suffix) == 1 then
					return cmd .. suffix
				end
			end
		end
		return cmd
	end

	local lm = lastmaker_hol()
	if vim.fn.executable(lm) == 1 then
		return lm
	end

	-- config.holdir is the documented "set one thing" option: the binary
	-- must derive from it too (NOT via M.holdir(), which calls back here)
	if M.config.holdir and M.config.holdir ~= "" then
		local hol = M.config.holdir .. "/bin/hol"
		if vim.fn.executable(hol) == 1 then
			return hol
		end
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
  Resolve the HOL installation root (Phase 7b). Priority:
    1. config.holdir (explicit)
    2. derived from the hol binary actually being run -- which_hol()
       resolved through $PATH and symlinks; <root>/bin/hol implies <root>,
       accepted when it looks like a HOL tree (has tools/)
    3. $HOLDIR (last resort, e.g. layouts where hol is not under a bin/)
  holdeptool (hl), the default global fifo path, and vimhol.sml discovery
  (7a) all route through this, so one `holdir` option -- or nothing at all,
  when hol itself is discoverable -- configures everything.
--]]
M.holdir = function()
	if M.config.holdir and M.config.holdir ~= "" then
		return M.config.holdir
	end

	local hol = M.which_hol()
	if hol ~= "" then
		local abs = vim.fn.exepath(hol)
		if abs ~= "" then
			abs = vim.uv.fs_realpath(abs) or abs
			local bindir = vim.fn.fnamemodify(abs, ":h")
			if vim.fn.fnamemodify(bindir, ":t") == "bin" then
				local root = vim.fn.fnamemodify(bindir, ":h")
				if vim.fn.isdirectory(root .. "/tools") == 1 then
					return root
				end
			end
		end
	end

	local env = vim.env.HOLDIR
	if env and env ~= "" then
		return env
	end

	return nil
end

--[[
  Locate vimhol.sml for the auto-bootstrap (Phase 7a). config.vimhol:
    true (default) -- discover under holdir()
    "/path"        -- explicit file
    false          -- bootstrap disabled
  Returns nil when disabled or not found.
--]]
M.vimhol_sml = function()
	local cfg = M.config.vimhol
	if cfg == false then
		return nil
	end
	if type(cfg) == "string" and cfg ~= "" then
		return cfg
	end
	local holdir = M.holdir()
	if holdir then
		for _, rel in ipairs({
			"/tools/editor-modes/vim/vimhol.sml",
			"/tools/vim/vimhol.sml", -- layout before the editor-modes rename
		}) do
			if vim.fn.filereadable(holdir .. rel) == 1 then
				return holdir .. rel
			end
		end
	end

	-- Fallback: vimhol.sml sits beside the fifo in the default layout. When
	-- holdir can't be resolved but a fifo path is known ($VIMHOL_FIFO or
	-- config.fifo), look there -- this is what stops the external-session
	-- recipe from degrading to a "<HOLDIR>" placeholder.
	local fpath = require("hol4nvim.fifo").path()
	if fpath then
		local cand = vim.fn.fnamemodify(fpath, ":h") .. "/vimhol.sml"
		if vim.fn.filereadable(cand) == 1 then
			return cand
		end
	end

	return nil
end

-- Escape a Lua string as an SML double-quoted literal (quotes included).
local function sml_str(s)
	return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--[[
  One SML statement that loads vimhol.sml unless the session already has it
  (a ~/.hol-config.sml may have `use`d it first): #lookupStruct sees whether
  the top-level Vimhol structure is bound. Shared by the 7a bootstrap and
  the 7c external-session recipe.
--]]
local function guarded_use(path)
	return 'val _ = (case #lookupStruct PolyML.globalNameSpace "Vimhol" of'
		.. ' NONE => use '
		.. sml_str(path)
		.. ' | SOME _ => ());'
end

--[[
  Auto-bootstrap Vimhol into a freshly spawned REPL (Phase 7a), replacing
  upstream's hand-edited ~/.hol-config.sml. Without Vimhol tailing the
  session's pipe, multi-line sends and hc silently degrade to the raw pty.

  Fed straight into the pty, NOT through send(): the pipe this enables is
  not up yet. No timing games either -- hol evaluates stdin only after
  check-intconfig.sml has run any ~/.hol-config.sml / $HOL_CONFIG, so the
  lookupStruct guard reliably sees whether the user's own config already
  loaded Vimhol and no-ops instead of attaching a second tail to the pipe.
  Each line is one complete statement, so a failing `use` cannot swallow
  the rest: quietdec is always toggled back and the sentinel always
  prints. The sentinel is built with `^` so the echoed input line cannot
  match a "hol4nvim: vimhol ready" search -- only the print output does.
--]]
local function bootstrap_vimhol(job)
	local path = M.vimhol_sml()
	if not path then
		if M.config.vimhol ~= false then
			vim.notify(
				"hol4nvim: vimhol.sml not found -- multi-line sends and the"
					.. " interrupt keymap degrade to the raw pty. Set"
					.. " config.holdir or config.vimhol"
					.. " (config.vimhol = false silences this).",
				vim.log.levels.WARN
			)
		end
		return
	end
	vim.fn.chansend(job, table.concat({
		"val _ = HOL_Interactive.toggle_quietdec();",
		guarded_use(path),
		"val _ = HOL_Interactive.toggle_quietdec();",
		'val _ = print ("hol4nvim: vimhol" ^ " ready\\n");',
		"",
	}, "\n"))
end

--[[
  Paste-able recipe for attaching an EXTERNAL HOL session to the fifo
  (Phase 7c). The plugin cannot bootstrap a REPL it did not spawn, so the
  "no fifo reader" warning hands the user the exact commands instead --
  and creates the fifo, so the pasted hol finds a working pipe.
--]]
M.external_recipe = function()
	local fifo = require("hol4nvim.fifo")
	local path = fifo.path()
	if not path then
		return "no fifo path resolves -- set config.fifo or config.holdir"
	end
	if not fifo.ensure(path) then
		return path .. " exists but is not a fifo -- remove it or point config.fifo elsewhere"
	end
	local paste
	local vimhol = M.vimhol_sml()
	if vimhol then
		paste = guarded_use(vimhol)
	else
		paste = 'use "<HOLDIR>/tools/editor-modes/vim/vimhol.sml";'
	end
	return "in a terminal:  VIMHOL_FIFO='"
		.. path
		.. "' hol\npaste into it:  "
		.. paste
		.. "\nor set it up once, permanently:  :HolExternalSetup"
end

--[[
  External-session auto-setup (out-of-the-box `hl`/`hs` against a hol you start
  in your own terminal). The plugin cannot inject into a hol it did not spawn,
  so it instead writes a loader that hol's own config mechanism picks up:
  pointing $HOL_CONFIG at hol_config_path() makes any hol attach Vimhol to the
  fifo. See :HolExternalSetup, which prints the one export line to add.

  The loader lives in Neovim's data dir (one managed file), NOT ~/.hol-config.sml.
--]]
M.hol_config_path = function()
	return vim.fn.stdpath("data") .. "/hol4nvim/hol-config.sml"
end

--[[
  The loader's SML. Machine-agnostic by construction: $HOME is read at
  hol-runtime (no home path is baked in) and vimhol.sml is located from $HOLDIR
  at runtime, falling back to the `vimhol_path` hol4nvim resolved here. Because
  $HOL_CONFIG REPLACES hol's own ~/.hol-config.sml search (check-intconfig.sml),
  the loader runs the user's own hol-config first, then attaches Vimhol --
  guarded via #lookupStruct so a config that already loaded Vimhol is not loaded
  (and re-tailed) twice. Identifiers are letter-first (hnv_*) for the SML lexer.
--]]
local hol_config_template = [[
(* hol4nvim: generated Vimhol loader -- DO NOT EDIT (regenerated on setup).
   Point $HOL_CONFIG at this file so `hol` attaches Vimhol to the fifo and
   hol4nvim can drive an external session (see :HolExternalSetup). $HOL_CONFIG
   replaces hol's own ~/.hol-config.sml search, so we run your hol-config first,
   then attach Vimhol (guarded, so a preloading config is not re-tailed). *)
local
  fun hnv_readable f =
    (OS.FileSys.access (f, [OS.FileSys.A_READ])
     andalso not (OS.FileSys.isDir f)) handle OS.SysErr _ => false
  fun hnv_useFirst [] = ()
    | hnv_useFirst (f :: fs) =
        if hnv_readable f then use f else hnv_useFirst fs
  val hnv_vimhol =
    (case OS.Process.getEnv "HOLDIR" of
         SOME hnv_d => [OS.Path.concat (hnv_d, "tools/editor-modes/vim/vimhol.sml"),
                        OS.Path.concat (hnv_d, "tools/vim/vimhol.sml")]
       | NONE => []) @ [%s]
in
  val () =
    (case OS.Process.getEnv "HOME" of
         NONE => ()
       | SOME hnv_home =>
           hnv_useFirst (List.map (fn n => OS.Path.concat (hnv_home, n))
             ["hol-config.sml", "hol-config.ML", ".hol-config",
              ".hol-config.sml", ".hol-config.ML"]));
  val () =
    (case #lookupStruct PolyML.globalNameSpace "Vimhol" of
         NONE => hnv_useFirst hnv_vimhol
       | SOME _ => ())
end;
]]

M.hol_config_content = function(vimhol_path)
	return string.format(hol_config_template, sml_str(vimhol_path))
end

--[[
  Write the loader to hol_config_path(), returning the path. Regenerated in
  place on every call so it always reflects the current vimhol.sml resolution.
  Returns nil plus a reason when vimhol.sml cannot be resolved (there would be
  nothing useful to load) -- callers surface it.
--]]
M.write_hol_config = function()
	local vimhol = M.vimhol_sml()
	if not vimhol then
		return nil, "vimhol.sml not resolved (set config.holdir or config.vimhol)"
	end
	local path = M.hol_config_path()
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile(
		vim.split(M.hol_config_content(vimhol), "\n", { plain = true }),
		path
	)
	return path
end

--[[
  The environment an external hol needs to attach to this plugin's fifo:
  HOL_CONFIG -> the generated loader (attaches Vimhol), VIMHOL_FIFO -> the exact
  fifo hol4nvim sends to, so both sides agree regardless of vimhol.sml's own
  compiled-in default. Writes the loader and ensures the fifo exists. Returns
  nil plus a reason when either path cannot be resolved.
--]]
M.external_env = function()
	local path, reason = M.write_hol_config()
	if not path then
		return nil, reason
	end
	local fifo = require("hol4nvim.fifo")
	local fpath = fifo.path()
	if not fpath then
		return nil, "no fifo path (set config.fifo or config.holdir)"
	end
	fifo.ensure(fpath)
	return { HOL_CONFIG = path, VIMHOL_FIFO = fpath }
end

--[[
  Managed shell-rc block (opt-in, only on an explicit :HolExternalSetup). We
  write the derived export lines between markers so re-running updates them in
  place and deleting the block removes them cleanly -- the plugin never edits a
  shell rc on setup(), only when the user asks. Fish needs `set -gx`, not
  `export`; both marker lines are ordinary comments in either shell.
--]]
M.rc_marker_begin = "# >>> hol4nvim (managed) >>>"
M.rc_marker_end = "# <<< hol4nvim (managed) <<<"

local function sh_squote(s) -- POSIX single-quote (…'\''… for embedded quotes)
	return "'" .. s:gsub("'", "'\\''") .. "'"
end
local function fish_squote(s) -- fish single-quote (backslash-escapes \ and ')
	return "'" .. s:gsub("\\", "\\\\"):gsub("'", "\\'") .. "'"
end

-- "fish" when the rc/shell name says so, else "posix" (zsh/bash/sh).
M.rc_shell_kind = function(hint)
	local name = vim.fn.fnamemodify(hint or vim.env.SHELL or "", ":t")
	if name:match("fish") then
		return "fish"
	end
	return "posix"
end

-- The default rc for $SHELL, or nil when we can't tell (caller asks for a path).
M.default_rc = function()
	local shell = vim.fn.fnamemodify(vim.env.SHELL or "", ":t")
	if shell == "zsh" then
		return vim.fn.expand("~/.zshrc")
	elseif shell == "bash" then
		return vim.fn.expand("~/.bashrc")
	elseif shell == "fish" then
		return vim.fn.expand("~/.config/fish/config.fish")
	end
	return nil
end

-- The managed block for `env` in `kind` ("posix"/"fish") syntax, markers included.
M.shell_rc_block = function(env, kind)
	local set
	if kind == "fish" then
		set = function(n, v)
			return "set -gx " .. n .. " " .. fish_squote(v)
		end
	else
		set = function(n, v)
			return "export " .. n .. "=" .. sh_squote(v)
		end
	end
	return {
		M.rc_marker_begin,
		"# hol started in your terminal attaches Vimhol to hol4nvim's fifo.",
		"# Managed by :HolExternalSetup -- re-run to update, delete this block to undo.",
		set("HOL_CONFIG", env.HOL_CONFIG),
		set("VIMHOL_FIFO", env.VIMHOL_FIFO),
		M.rc_marker_end,
	}
end

-- Splice `block` into `existing` (list of lines): replace an existing marked
-- block in place, else append it after a blank separator. Returns the new lines
-- and whether a block was replaced (vs. added). Pure -- unit-tested directly.
M.splice_rc = function(existing, block)
	local out, replaced = {}, false
	local i, n = 1, #existing
	while i <= n do
		if existing[i] == M.rc_marker_begin then
			for _, l in ipairs(block) do
				out[#out + 1] = l
			end
			replaced = true
			while i <= n and existing[i] ~= M.rc_marker_end do
				i = i + 1
			end
			i = i + 1 -- step past the end marker (or past EOF if unterminated)
		else
			out[#out + 1] = existing[i]
			i = i + 1
		end
	end
	if not replaced then
		if #out > 0 and out[#out] ~= "" then
			out[#out + 1] = ""
		end
		for _, l in ipairs(block) do
			out[#out + 1] = l
		end
	end
	return out, replaced
end

--[[
  Write the managed export block to a shell rc, resolved in precedence order:
  the explicit `target` (from `:HolExternalSetup <path>`), then config.shell_rc,
  then the default rc for $SHELL. Idempotent: an existing block is rewritten in
  place with current paths. Returns { path, action = "updated"|"added", env } or
  nil plus a reason (no fifo/vimhol, or no detectable shell). Only
  :HolExternalSetup calls this -- setup() never touches a shell rc.
--]]
M.write_shell_rc = function(target)
	local env, reason = M.external_env()
	if not env then
		return nil, reason
	end
	local configured = M.config.shell_rc
	local path = (target and target ~= "") and target
		or (configured and configured ~= "" and configured)
		or M.default_rc()
	if not path then
		return nil,
			"could not detect your shell rc from $SHELL -- set config.shell_rc or pass a path (e.g. :HolExternalSetup ~/.zshrc)"
	end
	path = vim.fs.normalize(path)
	local existing = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
	local block = M.shell_rc_block(env, M.rc_shell_kind(path))
	local out, replaced = M.splice_rc(existing, block)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	vim.fn.writefile(out, path)
	return { path = path, action = replaced and "updated" or "added", env = env }
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
      Set config.hol_cmd or config.holdir", vim.log.levels.ERROR)
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
	require("hol4nvim.fifo").ensure(pipe)

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
			"hol4nvim: failed to start hol (" .. cmd .. ")",
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

	bootstrap_vimhol(job)

	-- Announce the new session so higher layers (e.g. completion) can react
	-- without repl depending on them. Fired after the session is recorded and
	-- bootstrapped, so a listener's send() has a live transport.
	vim.api.nvim_exec_autocmds("User", { pattern = "HolReplStarted", modeline = false })

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
		local fifo = require("hol4nvim.fifo")
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
			"hol4nvim: not sent -- incomplete block, no closing '"
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
		local fifo = require("hol4nvim.fifo")
		if fifo.ready() then
			fifo.send(text)
		else
			vim.notify(
				"hol4nvim: no in-vim REPL and no fifo reader.\n"
					.. M.external_recipe()
					.. "\n(or start an in-vim REPL with the open keymap)",
				vim.log.levels.WARN
			)
		end
	else
		vim.notify(
			"hol4nvim: transport=terminal but no in-VIM REPL",
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
			"hol4nvim: not sent -- unclosed comment: a '(*' on line "
				.. unclosed
				.. " of the selection has no matching '*)'. SML comments"
				.. " nest, so every '(*' inside a comment needs its own '*)'.",
			vim.log.levels.WARN
		)
		return nil
	end
	if not text:find("%S") then
		vim.notify(
			"hol4nvim: nothing to send (only comments/whitespace)",
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
  equivalent; mapped to h! and :HolSendDocument). `open` declarations are
  dropped: in an interactive session, `open` of a theory that is not loaded
  yet fails -- use the load keymap (hl) over the open lines first instead.
  An `open` may span lines; it is taken to continue over nonblank lines of
  bare identifiers, ending at one that carries a ";".

  New-style script headers (`Theory name` + `Ancestors`/`Libs` name lists)
  are dropped for the same reason: their interactive meaning IS opens of
  possibly-unloaded theories -- hl over the header handles them. A section's
  names may sit on the keyword line or on indented continuation lines;
  blank lines only continue the header when a section keyword follows.
--]]
local header_section = "^Ancestors%f[%W][%s%w_.']*$"
local header_section2 = "^Libs%f[%W][%s%w_.']*$"

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
		elseif line:find("^Theory%f[%W]") then
			i = i + 1
			while i <= #lines do
				local hdr = lines[i]
				if hdr:find(header_section) or hdr:find(header_section2) then
					i = i + 1
				elseif hdr:find("^%s+[%w_.'][%s%w_.']*$") then
					i = i + 1 -- indented bare-name continuation
				elseif hdr:find("^%s*$") then
					local j = i + 1
					while j <= #lines and lines[j]:find("^%s*$") do
						j = j + 1
					end
					if
						j <= #lines
						and (lines[j]:find(header_section) or lines[j]:find(header_section2))
					then
						i = j + 1
					else
						break
					end
				else
					break
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
		vim.cmd("normal! \27") -- h! pressed from visual mode: leave it
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

-- Resolve holdeptool.exe: next to the chosen hol, else under holdir()/bin
-- (the next-to-hol branch keeps odd layouts working without any config).
local function holdeptool()
	local hol = M.which_hol()
	if hol ~= "" then
		local abs = vim.fn.exepath(hol)
		if abs ~= "" then
			local tool = vim.fn.fnamemodify(abs, ":h") .. "/holdeptool.exe"
			if vim.fn.executable(tool) == 1 then
				return tool
			end
		end
	end
	local holdir = M.holdir()
	if holdir then
		local tool = holdir .. "/bin/holdeptool.exe"
		if vim.fn.executable(tool) == 1 then
			return tool
		end
	end
	return ""
end
-- Exposed for :checkhealth (health.lua) so it probes exactly what hl uses.
M.holdeptool = holdeptool

local function send_load(text)
	text = stripped_or_warn(text)
	if not text then
		return
	end

	local tool = holdeptool()
	if tool == "" then
		vim.notify(
			"hol4nvim: holdeptool.exe not found (set config.holdir)",
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
			"hol4nvim: holdeptool failed:\n" .. table.concat(deps, "\n"),
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
		vim.notify("hol4nvim: no dependencies to load", vim.log.levels.INFO)
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

	-- Newly loaded theories bring new theorems into the DB; let listeners
	-- (completion) resnapshot. Same decoupling as HolReplStarted.
	vim.api.nvim_exec_autocmds("User", { pattern = "HolLoaded", modeline = false })
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
  Display toggles (port of the hy and hn mappings, hol.vim:272-273).
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
	local fifo = require("hol4nvim.fifo")
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
	vim.notify("hol4nvim: no HOL session to interrupt", vim.log.levels.WARN)
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
