--[[
  End-to-end test: drives examples/TestScript.sml against a REAL hol REPL in
  a :terminal and asserts on the terminal buffer. Needs a working HOL4
  (hol on $PATH, $HOLDIR, or a .HOLMK/lastmaker).
      nvim --headless -u init.lua -l tests/e2e.lua examples/TestScript.sml
--]]

local t = dofile("tests/util.lua")

vim.o.swapfile = false
vim.cmd.edit((assert(_G.arg[1], "usage: ... -l tests/e2e.lua <XScript.sml>")))
t.check("filetype detected", vim.bo.filetype == "hol4script")

local repl = require("hol4nvim.repl")

-- record hol4nvim's own reporting (and surface it in the test log)
local notifications = {}
vim.notify = function(msg, level)
	table.insert(notifications, msg)
	print(("[notify %s] %s"):format(tostring(level), msg))
end

if repl.which_hol() == "" then
	t.fatal("hol not found: e2e needs HOL4 (set $HOLDIR). Run `make test-unit` for the HOL-free tier.")
end

-- Boot hol with NO user config (check-intconfig.sml honours HOL_NOCONFIG):
-- everything Vimhol-dependent below (pipe-routed multi-line sends, \c) then
-- proves the plugin's own 7a bootstrap, not a ~/.hol-config.sml on the
-- development machine.
vim.env.HOL_NOCONFIG = "1"

repl.open()
local session = repl.current()
if not session then
	t.fatal("repl.open() produced no session")
end

local function term_text()
	return table.concat(vim.api.nvim_buf_get_lines(session.buf, 0, -1, false), "\n")
end

local function occurrences(hay, needle)
	local n, pos = 0, 1
	while true do
		local s, e = hay:find(needle, pos, true)
		if not s then
			return n
		end
		n, pos = n + 1, e + 1
	end
end

-- Wait until `pat` (plain text) shows up in the REPL buffer `want` times
-- (default once) -- repeated workflows (goal set/proved) need counting.
-- Newlines are dropped before matching: the terminal hard-wraps long
-- output, which would otherwise split a needle mid-word.
local function wait_for(name, pat, ms, want)
	want = want or 1
	local ok = vim.wait(ms or 30000, function()
		return occurrences(term_text():gsub("\n", ""), pat) >= want
	end, 200)
	if not ok then
		-- dump the REPL tail so failures are debuggable from the log
		local lines = vim.api.nvim_buf_get_lines(session.buf, 0, -1, false)
		local last = #lines
		while last > 1 and lines[last] == "" do
			last = last - 1
		end
		for i = math.max(1, last - 20), last do
			print("  | " .. lines[i])
		end
	end
	return t.check(name, ok, "never saw " .. vim.inspect(pat) .. " x" .. want)
end

-- Put the cursor on the first line matching a vim regex.
local function goto_line(pat)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
	if vim.fn.search(pat, "cW") == 0 then
		t.fatal("example file has no line matching " .. pat)
	end
end

-- hol takes a while to boot; wait for the bootstrap sentinel, printed only
-- after the guarded `use vimhol.sml` completed (the echoed input line cannot
-- match: the sentinel source is split with ^). Then give Vimhol's fifo tail
-- a moment to attach -- otherwise the first multi-line send falls back to
-- the echoed pty path.
wait_for("REPL ready (vimhol bootstrapped)", "hol4nvim: vimhol ready", 90000)
vim.wait(2000)

-- \l : load deps from the open line; full HOLLoad shape also executes the
-- open itself quietly and prints the confirmation
goto_line("^open HolKernel")
repl.send_load_line()
wait_for("\\l loads deps and confirms", "HOLLoad HolKernel", 60000)

-- \s : send a single line
goto_line("^val two")
repl.send_line()
wait_for("\\s evaluates line", "val two = 2")

-- \s visual, ACTIVE visual mode: send while the selection is still live,
-- exactly as the keymaps do (regression: gv-based reselect sent stale junk)
goto_line("^fun triple")
vim.cmd("normal! V2j")
t.check("visual mode is active", vim.fn.mode() == "V")
repl.send_visual()
wait_for("\\s active-visual sends fun", "val triple = fn")

goto_line("^val it_should_be_nine")
repl.send_line()
wait_for("visual-sent fun works", "val it_should_be_nine = 9")

-- \u quiet send: binding evaluates but its printout is suppressed. The
-- probe goes multi-line so it queues on the same Vimhol pipe (ordering).
goto_line("^val quietly = 99")
repl.send_quiet_line()
repl.send("val quietly_check =\n  quietly + 1;")
wait_for("\\u quiet value usable afterwards", "val quietly_check = 100")
t.check(
	"\\u suppressed the binding printout",
	occurrences(term_text():gsub("\n", ""), "val quietly = 99") == 0
)

-- goal workflow: set goal via \s, prove via \e
goto_line("^proofManagerLib.g `!a b")
repl.send_line()
wait_for("goal is set", "Initial goal:")

goto_line("^decide_tac")
repl.send_expand_line()
wait_for("\\e proves goal", "Initial goal proved")

goto_line("^proofManagerLib.drop")
repl.send_line()

-- \g : set the goal straight from the bare quotation line, prove, drop
goto_line("^`!a b\\. a + b")
repl.send_goal_line()
wait_for("\\g sets goal", "Initial goal:", 30000, 2)

goto_line("^decide_tac")
repl.send_expand_line()
wait_for("\\e proves \\g goal", "Initial goal proved", 30000, 2)

goto_line("^proofManagerLib.drop")
repl.send_line()

-- \S : with the sub_add goal set, split off `0 < n` as a subgoal
goto_line("^`!n\\. 1 <= n")
repl.send_goal_line()
wait_for("\\g sets sub_add goal", "Initial goal:", 30000, 3)

-- anchored with $: comments and the 3d demo line mention these strings too
goto_line("^\\s*rpt strip_tac$")
repl.send_expand_line()
-- HOL's goal display uses unicode minus (−), unlike the ASCII echo;
-- initial goal display + post-strip_tac display = 2
wait_for("strip_tac leaves arith goal", "n − 1 + 1 = n", 30000, 2)

-- select `0 < n` by decide_tac (without the leading >>), then \S;
-- like upstream, \S strips the trailing by-clause but not leading tokens.
-- The <Esc> before sending covers the mark-based (gv) fallback path.
goto_line("^\\s*>> `0 < n` by decide_tac")
vim.fn.search("`0 < n", "c")
vim.cmd("normal! v$\27")
repl.send_subgoal_visual()
-- echo of the sg(...) command + the new subgoal display = 2
wait_for("\\S sets subgoal", "0 < n", 30000, 2)

-- \b backup undoes the sg: the arith goal is displayed again (3rd unicode
-- display: initial, post-strip_tac, now this)
repl.backup()
wait_for("\\b backs up a step", "n − 1 + 1 = n", 30000, 3)

-- \p prints the current proof state: same goal, 4th display
repl.p()
wait_for("\\p prints proof state", "n − 1 + 1 = n", 30000, 4)

-- \c reaches Vimhol's poller over the session pipe (no tactic is running,
-- so it reports the interrupt and that there is nothing to interrupt)
repl.interrupt()
wait_for("\\c reaches Vimhol", "Vim interrupt")

-- \e on the WHOLE `>> ... by ...` line: the leading >> is combinator noise
-- from the proof script; expand strips it and applies the by-tactic
-- (echo of the expand + the new assumption display = occurrences 3 and 4)
goto_line("^\\s*>> `0 < n` by decide_tac")
repl.send_expand_line()
wait_for("\\e strips >> and applies by-line", "0 < n", 30000, 4)

goto_line("^decide_tac")
repl.send_expand_line()
wait_for("\\e finishes sub_add proof", "Initial goal proved", 30000, 3)

goto_line("^proofManagerLib.drop")
repl.send_line()

-- \G unquoted goal: select the statement + Proof lines of a Theorem block
-- (no backquotes) and set it as the goal via new_goalstack/mk_tacmod
goto_line("^Theorem add_comm_test")
vim.cmd("normal! jVj") -- the goal line and the Proof line
repl.send_uqgoal_visual()
wait_for("\\G sets unquoted goal", "Initial goal:", 30000, 4)

goto_line("^decide_tac")
repl.send_expand_line()
wait_for("\\e proves \\G goal", "Initial goal proved", 30000, 4)

goto_line("^proofManagerLib.drop")
repl.send_line()

-- proof-manager control tour (example section 6): conj_tac splits the goal,
-- rotate/save run, simp proves a subgoal, backup/restore/drop wind down
goto_line("^`T /\\\\ (1 + 1 = 2)`")
repl.send_goal_line()
wait_for("control-tour goal set", "Initial goal:", 30000, 5)

goto_line("^conj_tac")
repl.send_expand_line()
wait_for("conj_tac splits into two subgoals", "2 subgoals")

repl.rotate(1)
repl.save()
goto_line("^simp\\[\\]")
repl.send_expand_line()
wait_for("simp proves a subgoal", "Goal proved")

repl.backup()
repl.restore()
repl.drop()

-- \c stops a runaway tactic (example section 7): the two-line rpt
-- ONCE_REWRITE_TAC loop goes via the Vimhol pipe, so interrupt reaches it
goto_line("^`!a b\\. a + b + b")
repl.send_goal_line()
wait_for("runaway-demo goal set", "Initial goal:", 30000, 6)

goto_line("^rpt (ONCE_REWRITE_TAC")
vim.cmd("normal! Vj")
repl.send_expand_visual()
vim.wait(3000) -- let the loop actually start spinning
repl.interrupt()
wait_for("\\c stops the runaway tactic", "Vim interrupt", 30000, 2)

-- Vimhol quirk (upstream too): a file delivered while the interrupted
-- runner thread is still dying is queued but not started; the NEXT
-- delivery kicks a fresh runner. Wait, then send a multi-line probe that
-- both restarts the runner and proves it recovered.
vim.wait(5000)
repl.send("val interrupted_ok =\n  true;")
wait_for("runner recovers after interrupt", "interrupted_ok = true")
repl.drop()

-- section 3d: the combinator-stripping demo lines drive a real proof --
-- trailing >> stripped on the first, leading >> on the second, trailing
-- THEN on the third after a restart
goto_line("^`!n\\. n <= n + n`")
repl.send_goal_line()
wait_for("3d goal set", "Initial goal:", 30000, 7)

goto_line("^rpt strip_tac >>")
repl.send_expand_line()
goto_line("^>> decide_tac")
repl.send_expand_line()
wait_for("noisy >> lines prove the goal", "Initial goal proved", 30000, 5)

repl.restart()
goto_line("^decide_tac THEN")
repl.send_expand_line()
wait_for("trailing THEN line proves it again", "Initial goal proved", 30000, 6)
repl.drop()

-- \s on a whole Theorem..QED block in active visual mode: the script-file
-- syntax goes through hol's filter and produces a thm binding
goto_line("^Theorem add_comm_test")
vim.cmd("normal! V4j")
repl.send_visual()
wait_for("\\s sends Theorem block", "val add_comm_test =")

-- incomplete Theorem block (selection stops before QED): refused with a
-- warning instead of wedging hol's filter at the '#' prompt
goto_line("^Theorem add_comm_test")
vim.cmd("normal! V3j")
local before = #notifications
repl.send_visual()
t.check(
	"incomplete block refused with warning",
	#notifications > before
		and notifications[#notifications]:find("incomplete block") ~= nil
)

-- ...and the REPL is still healthy, not stuck mid-construct
goto_line("^val two")
repl.send_line()
wait_for("REPL healthy after refused send", "val two = 2", 30000, 2)

-- comments in the selection are stripped: select the section-7 comment
-- banner plus the val line and send it all
goto_line("^val comments_ok")
vim.cmd("normal! V4k")
repl.send_visual()
wait_for("comments stripped from send", "val comments_ok = 42")

-- a comment-only selection is not sent at all
goto_line("^(\\* 8\\.")
vim.cmd("normal! Vj")
local before_comment = #notifications
repl.send_visual()
t.check(
	"comment-only selection not sent",
	#notifications > before_comment
		and notifications[#notifications]:find("nothing to send") ~= nil
)

-- \y and \n display toggles (example section 8b): observable via how the
-- quotation results print; both toggled straight back
repl.toggle_types()
goto_line("^``1 + 2``")
repl.send_line()
wait_for("\\y shows types", "(1 :num)")
repl.toggle_types()

repl.toggle_unicode()
goto_line("^``¬T``")
repl.send_line()
wait_for("\\n prints ASCII negation", "~T")
repl.toggle_unicode()

-- \e on a non-tactic: HOL errors, nvim survives
goto_line("^val this_is_not_a_tactic")
local ok = pcall(repl.send_expand_line)
t.check("\\e on non-tactic does not raise", ok)

-- \! send_document on the dedicated linear demo (examples/WholeScript.sml):
-- opens dropped, comments stripped (including one mentioning Theorem with
-- no QED), Theorem and Definition blocks all evaluate. arithmeticTheory is
-- already loaded from the \l step above, as the demo's workflow instructs.
vim.cmd.edit("examples/WholeScript.sml")
local before_doc = #notifications
repl.send_document()
t.check("send_document not blocked by guard", #notifications == before_doc)
wait_for("WholeScript: fun/val evaluate", "val four = 4")
wait_for("WholeScript: theorem proves", "val whole_add =")
wait_for("WholeScript: multi-step theorem proves", "val whole_sub =")
wait_for("WholeScript: Definition accepted", "val double_def =")
wait_for("WholeScript: theorem uses the Definition", "val dbl_even =")
t.check(
	"send_document dropped the open line",
	occurrences(term_text():gsub("\n", ""), "open HolKernel") == 0
)

-- \X : close sends EOF and the job dies, pruning the session stack
repl.close()
local closed = vim.wait(15000, function()
	return repl.current() == nil
end, 200)
t.check("\\X ends session and prunes stack", closed)

t.finish()
