--[[
  hol4nvim.search -- query the live HOL session's theorem database from an
  interactive panel.

  hf/hm (or :HolFind/:HolMatch) open a horizontal split of the focused window:
  line 1 is a header denoting the search type, line 2 is an editable query
  "bar", and the rest holds the results. Type a query and press <CR> to run it
  in place; press <CR> on a result line to insert that theorem's name at the
  cursor in the window the panel was opened from; q closes the panel.

  The plugin's send() is one-way: there is no channel to read HOL's answers
  back. So instead of scraping the REPL, the query is pure SML that FORMATS
  the hits into a string and writes them to a temp file, ending with a
  sentinel line; Neovim polls that file and renders it. Because we format the
  string ourselves (Parse.thm_to_string), the print_depth-0 echo suppression
  on piped sessions is irrelevant.

  Two searches:
    - name  (DB.find "str")           -- substring match on theory.name
    - term  (DB.apropos ``pattern``)  -- theorems whose subterms match a term

  The whole query is wrapped in a handler that ALWAYS writes the sentinel, so
  a bad term pattern (parse failure, unknown constant) shows an error line
  instead of hanging the poll.
--]]

local M = {}

-- Marker the SML appends once the file is fully written; the poll waits for it.
M.SENTINEL = "===HOLSEARCH_DONE==="

-- Escape a Lua string into an SML string literal.
local function sml_string(s)
	return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--[[
  Build the SML for one query. `expr` is an SML expression of type
  DB.public_data list; `outfile` is where the formatted result is written.
  Exposed shape is deterministic so it can be unit-tested without HOL.
--]]
local function build(expr, outfile)
	local out = sml_string(outfile)
	-- Internal bindings are prefixed `hnv_` (a valid SML identifier -- must
	-- start with a letter, not "_") to avoid clashing with user bindings.
	return table.concat({
		"val () = (",
		"  (let",
		"     val hnv_hits = (" .. expr .. ")",
		'     fun hnv_f ((thy,nm),(th,_,_)) = thy ^ "." ^ nm ^ ": " ^ Parse.thm_to_string th',
		'     val hnv_body = String.concatWith "\\n" (List.map hnv_f hnv_hits)',
		"     val hnv_os = TextIO.openOut " .. out,
		"   in",
		'     TextIO.output(hnv_os, hnv_body ^ "\\n' .. M.SENTINEL .. ' (" ^ Int.toString (length hnv_hits) ^ " hits)\\n");',
		"     TextIO.closeOut hnv_os",
		"   end)",
		"  handle hnv_e =>",
		"   (let val hnv_os = TextIO.openOut " .. out,
		'    in TextIO.output(hnv_os, "search error: " ^ General.exnMessage hnv_e ^ "\\n' .. M.SENTINEL .. ' (error)\\n");',
		"       TextIO.closeOut hnv_os end)",
		");",
	}, "\n")
end

--- SML for a name search (substring match on theorem names). Pure/testable.
M.find_cmd = function(query, outfile)
	return build("DB.find " .. sml_string(query), outfile)
end

--- SML for a term search. The pattern is parsed INSIDE the guarded expression,
--- so a parse failure is caught and reported rather than thrown. Pure/testable.
M.match_cmd = function(query, outfile)
	return build("DB.apropos (Parse.Term [QUOTE " .. sml_string(query) .. "])", outfile)
end

-- A live transport must exist, or send() would only warn and the poll would
-- pointlessly time out. Mirror send()'s routing decision.
local function transport_ready()
	local repl = require("hol4nvim.repl")
	local mode = repl.config.transport or "auto"
	if mode ~= "fifo" and repl.current() then
		return true
	end
	if mode ~= "terminal" and require("hol4nvim.fifo").ready() then
		return true
	end
	return false
end

-- Read `outfile`; return body lines (sentinel stripped) and the summary tail,
-- or nil if the sentinel is not present yet.
local function read_result(outfile)
	local lines = vim.fn.readfile(outfile)
	local summary
	for i = #lines, 1, -1 do
		if lines[i]:find(M.SENTINEL, 1, true) then
			summary = lines[i]:gsub(".*" .. M.SENTINEL .. "%s*", "")
			table.remove(lines, i)
			return lines, summary
		end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Interactive panel. A horizontal split of the focused window whose first line
-- is a header denoting the search type, second line the editable query "bar",
-- and the rest the results. Type a query and press <CR> to run it in place.
-- ---------------------------------------------------------------------------
local state = { buf = nil, win = nil, kind = nil }

-- Line 1: the label that denotes which search this panel runs. <CR> on the bar
-- runs the search; <CR> on a result inserts its name (see M.on_enter).
local function header(kind)
	if kind == "term" then
		return "hm: search theorems by TERM (DB.apropos)    <CR>=run/pick  q=close"
	end
	return "hf: search theorems by NAME (DB.find)       <CR>=run/pick  q=close"
end

-- Replace the status line (3) and results (4+), preserving the header (1) and
-- the query bar (2). `body` nil -> status only; empty -> "(no matches)".
local function set_results(status, body)
	vim.bo[state.buf].modifiable = true
	local lines = { "--- " .. status .. " ---" }
	if body then
		if #body > 0 then
			vim.list_extend(lines, body)
		else
			lines[#lines + 1] = "(no matches)"
		end
	end
	vim.api.nvim_buf_set_lines(state.buf, 2, -1, false, lines)
end

--- Run the search for whatever is typed in the bar (line 2). Bound to <CR> in
--- the panel, and reused by M.run for a programmatic query. Blocks (vim.wait)
--- until the sentinel appears or the timeout elapses.
M.run_from_bar = function()
	if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
		return
	end
	vim.cmd("stopinsert")
	local query = vim.trim(vim.api.nvim_buf_get_lines(state.buf, 1, 2, false)[1] or "")
	if query == "" then
		return
	end
	if not transport_ready() then
		set_results("no HOL session -- start one with hx", nil)
		return
	end
	set_results("searching " .. query .. " ...", nil)
	vim.cmd("redraw")

	local outfile = vim.fn.tempname()
	pcall(os.remove, outfile)
	local cmd = (state.kind == "term") and M.match_cmd(query, outfile)
		or M.find_cmd(query, outfile)
	require("hol4nvim.repl").send(cmd)

	local done = vim.wait(15000, function()
		return vim.fn.filereadable(outfile) == 1 and read_result(outfile) ~= nil
	end, 100)
	if not done then
		set_results("timed out (no response from the REPL)", nil)
		return
	end
	local body, summary = read_result(outfile)
	pcall(os.remove, outfile)
	set_results(summary or "done", body or {})
	-- leave the cursor on the query bar so the next search is one edit away
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		pcall(vim.api.nvim_win_set_cursor, state.win, { 2, #query })
	end
end

-- Extract the theorem name from the result line at `row`, scanning up over any
-- continuation lines of a wrapped statement to its "thy.name:" header line.
local function name_at(row)
	for r = row, 4, -1 do
		local line = vim.api.nvim_buf_get_lines(state.buf, r - 1, r, false)[1] or ""
		local label = line:match("^([%w_'%.]+):")
		if label then
			return label:match("([^.]+)$") -- bare theorem name (drop the theory)
		end
	end
	return nil
end

--- Insert the theorem name from the result under the cursor into the window
--- the panel was opened from, at that window's cursor (and yank it too).
M.insert_result = function(row)
	local name = name_at(row)
	if not name then
		return
	end
	vim.fn.setreg('"', name)
	local ow = state.origin_win
	if ow and vim.api.nvim_win_is_valid(ow) then
		vim.api.nvim_set_current_win(ow)
		vim.api.nvim_put({ name }, "c", false, true) -- insert at the cursor
	else
		vim.notify(
			"hol4nvim: no origin window -- '" .. name .. "' yanked to the unnamed register",
			vim.log.levels.INFO
		)
	end
end

--- <CR> in the panel: on the header/bar/status (lines 1-3) run the search; on
--- a result line (4+) pick that result into the origin window.
M.on_enter = function()
	if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
		return
	end
	if vim.api.nvim_win_get_cursor(state.win)[1] >= 4 then
		M.insert_result(vim.api.nvim_win_get_cursor(state.win)[1])
	else
		M.run_from_bar()
	end
end

-- Open (or refocus) the panel as a horizontal split of the focused window,
-- seeded with `query` in the bar. `insert` drops into insert mode to type.
local function open_panel(kind, query, insert)
	state.kind = kind
	query = query or ""
	-- remember the window we came from, so picking a result inserts there
	local from = vim.api.nvim_get_current_win()
	if from ~= state.win then
		state.origin_win = from
	end
	if not (state.win and vim.api.nvim_win_is_valid(state.win)) then
		if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
			state.buf = vim.api.nvim_create_buf(false, true)
			local bo = vim.bo[state.buf]
			bo.buftype = "nofile"
			bo.bufhidden = "hide"
			bo.swapfile = false
			bo.buflisted = false
			pcall(vim.api.nvim_buf_set_name, state.buf, "hol-search")
			vim.keymap.set(
				{ "n", "i" },
				"<CR>",
				M.on_enter,
				{ buffer = state.buf, silent = true, desc = "HOL: run the search / pick a result" }
			)
			vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = state.buf, silent = true })
			-- best-effort holterm highlighting of the panel (the results are the
			-- point; the header/bar just tokenise harmlessly)
			pcall(vim.treesitter.start, state.buf, "holterm")
		end
		vim.cmd("split") -- horizontal split of the currently focused window
		state.win = vim.api.nvim_get_current_win()
		vim.api.nvim_win_set_buf(state.win, state.buf)
		pcall(vim.api.nvim_win_set_height, state.win, 14)
	else
		vim.api.nvim_set_current_win(state.win)
	end
	pcall(function()
		vim.wo[state.win].cursorline = true -- show which result is under the cursor
	end)
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
		header(kind),
		query,
		"--- type a query, then <CR> ---",
	})
	vim.api.nvim_win_set_cursor(state.win, { 2, #query })
	if insert then
		vim.cmd("startinsert!")
	end
end

--- hf / :HolFind -- open the name-search panel, bar seeded with <cword>.
M.find = function()
	open_panel("name", vim.fn.expand("<cword>"), true)
end

--- hm / :HolMatch -- open the term-search panel, bar seeded with <cword>.
M.match = function()
	open_panel("term", vim.fn.expand("<cword>"), true)
end

--- hm (visual) -- open the term-search panel seeded with the selection.
M.match_visual = function()
	local mode = vim.fn.mode()
	local sel = ""
	if mode == "v" or mode == "V" or mode == "\22" then
		local region =
			vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = mode })
		sel = table.concat(region, " ")
		vim.cmd("normal! \27") -- leave visual mode
	end
	open_panel("term", sel, true)
end

--[[
  Programmatic search (used by :HolFind/:HolMatch with an argument, and the
  tests): open the panel seeded with `query` and run it immediately. Returns
  the panel bufnr, or nil for an empty query.
--]]
M.run = function(kind, query)
	if not query or query == "" then
		return nil
	end
	open_panel(kind, query, false)
	M.run_from_bar()
	return state.buf
end

return M
