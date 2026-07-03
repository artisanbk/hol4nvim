--[[
  Unit tests: everything that runs without a HOL installation.
      nvim --headless -u init.lua -l tests/unit.lua
--]]

local t = dofile("tests/util.lua")

-- ftdetect: *Script.sml maps to hol4script
t.check(
	"ftdetect FooScript.sml",
	vim.filetype.match({ filename = "FooScript.sml" }) == "hol4script"
)
t.check(
	"ftdetect ignores plain .sml",
	vim.filetype.match({ filename = "foo.sml", buf = 0 }) ~= "hol4script"
)

-- setup() registered the user commands
t.check("command :HolStart", vim.fn.exists(":HolStart") == 2)
t.check("command :HolStop", vim.fn.exists(":HolStop") == 2)
t.check("command :HolSend", vim.fn.exists(":HolSend") == 2)
t.check("command :HolSendDocument", vim.fn.exists(":HolSendDocument") == 2)
t.check("command :HolUnabbrev", vim.fn.exists(":HolUnabbrev") == 2)

-- transform: pure string -> string layer
local transform = require("hol4nvim.transform")
local function expand_wraps(inner)
	return "proofManagerLib.expand(fn HOLgoal => (" .. inner .. ") HOLgoal)"
end
t.check(
	"transform.expand wraps tactic",
	transform.expand("rw[]") == expand_wraps("rw[]")
)
-- combinator-token stripping (upstream HOLExpand's s:strip* behaviour)
t.check(
	"expand strips leading >> (by-line case)",
	transform.expand("  >> `0 < n` by decide_tac")
		== expand_wraps("`0 < n` by decide_tac")
)
t.check(
	"expand strips trailing >>",
	transform.expand("rpt strip_tac >>") == expand_wraps("rpt strip_tac")
)
t.check(
	"expand strips trailing \\\\",
	transform.expand("simp[] \\\\") == expand_wraps("simp[]")
)
t.check(
	"expand strips leading THEN1",
	transform.expand("THEN1 decide_tac") == expand_wraps("decide_tac")
)
t.check(
	"expand strips trailing THEN",
	transform.expand("gen_tac THEN") == expand_wraps("gen_tac")
)
t.check(
	"expand strips stacked tokens",
	transform.expand(">- ( rw[] ) >>") == expand_wraps("( rw[] )")
)
t.check(
	"expand strips trailing by",
	transform.expand("`0 < n` by") == expand_wraps("`0 < n`")
)
t.check(
	"expand keeps mid-text combinators",
	transform.expand("tac1 >> tac2") == expand_wraps("tac1 >> tac2")
)
t.check(
	"expand keeps by inside words",
	transform.expand("standby") == expand_wraps("standby")
)
t.check(
	"expand keeps THEN glued to a word",
	transform.expand("THENfoo") == expand_wraps("THENfoo")
)
t.check(
	"expand keeps rw[] brackets",
	transform.expand("rw[] ,") == expand_wraps("rw[]")
)
t.check(
	"expand strips leading comma and closer",
	transform.expand(", rw[th]") == expand_wraps("rw[th]")
)
t.check(
	"transform.goal wraps quotation",
	transform.goal("`!x. x = x`") == "proofManagerLib.g(`!x. x = x`)"
)
t.check(
	"transform.goal strips trailing commas/whitespace",
	transform.goal("`!x. x = x`, \n") == "proofManagerLib.g(`!x. x = x`)"
)
t.check(
	"transform.subgoal strips trailing by-clause",
	transform.subgoal("`0 < n` by decide_tac")
		== "proofManagerLib.expand(bossLib.sg(`0 < n`))"
)
t.check(
	"transform.subgoal leaves bare term alone",
	transform.subgoal("`0 < n`")
		== "proofManagerLib.expand(bossLib.sg(`0 < n`))"
)
t.check(
	"transform.subgoal ignores 'by' inside words",
	transform.subgoal("`goodbye = standby`")
		== "proofManagerLib.expand(bossLib.sg(`goodbye = standby`))"
)
t.check(
	"transform.suffices strips trailing suffices_by-clause",
	transform.suffices("`n <> 0` suffices_by decide_tac")
		== "proofManagerLib.expand(bossLib.qsuff_tac(`n <> 0`))"
)
t.check(
	"transform.suffices not confused by subgoal 'by'",
	transform.subgoal("`n <> 0` suffices_by decide_tac")
		== "proofManagerLib.expand(bossLib.sg(`n <> 0` suffices_by decide_tac))"
)
t.check(
	"transform.pattern wraps selection",
	transform.pattern("`_ = _` >- rw[]")
		== "proofManagerLib.expand_list(Q.SELECT_GOAL_LT(`_ = _` >- rw[]))"
)
t.check(
	"transform.pattern strips tokens too",
	transform.pattern(">> `_ = _` >- rw[] >>")
		== "proofManagerLib.expand_list(Q.SELECT_GOAL_LT(`_ = _` >- rw[]))"
)

t.check(
	"transform.uqgoal bare goal",
	transform.uqgoal("!x. x = x")
		== 'proofManagerLib.new_goalstack([],``!x. x = x``)'
			.. ' (BasicProvers.mk_tacmod "Proof") I'
)
t.check(
	"transform.uqgoal splits at Proof line, keeps attributes",
	transform.uqgoal("!x. x = x\nProof[exclude_simps]")
		== 'proofManagerLib.new_goalstack([],``!x. x = x``)'
			.. ' (BasicProvers.mk_tacmod "Proof[exclude_simps]") I'
)
t.check(
	"transform.uqgoal joins lines after Proof",
	transform.uqgoal("!x. x = x\nProof[exclude_simps,\n   foo_def]")
		== 'proofManagerLib.new_goalstack([],``!x. x = x``)'
			.. ' (BasicProvers.mk_tacmod "Proof[exclude_simps, foo_def]") I'
)
t.check(
	"transform.uqgoal multi-line goal",
	transform.uqgoal("!x.\n  x = x\nProof")
		== 'proofManagerLib.new_goalstack([],``!x.\n  x = x``)'
			.. ' (BasicProvers.mk_tacmod "Proof") I'
)
t.check(
	"transform.uqgoal Resume header",
	transform.uqgoal("Resume foo_thm[case 1]:")
		== 'markerLib.set_suspended_goal {suspension_name = "foo_thm",'
			.. ' label_name = "case 1"}'
)
t.check(
	"transform.uqgoal Resume wins over Proof",
	transform.uqgoal("Resume t[l]:\nsome goal\nProof"):find("markerLib") == 1
)

t.check(
	"transform.quiet wraps in quietdec toggles",
	transform.quiet("open fooTheory")
		== "val _ = HOL_Interactive.toggle_quietdec();\n"
			.. "open fooTheory;\n"
			.. "val _ = HOL_Interactive.toggle_quietdec()"
)

-- strip_comments: the SML comment scanner
t.check(
	"strip_comments removes a simple comment",
	transform.strip_comments("rw[] (* easy *) >> simp[]") == "rw[]  >> simp[]"
)
t.check(
	"strip_comments handles nesting",
	transform.strip_comments("val x = (* a (* b *) c *) 1;") == "val x =  1;"
)
t.check(
	"strip_comments spans lines",
	transform.strip_comments("val a = 1; (* start\nQED\nend *)\nval b = 2;")
		== "val a = 1; \nval b = 2;"
)
t.check(
	"strip_comments leaves strings alone",
	transform.strip_comments('val s = "not a (* comment";')
		== 'val s = "not a (* comment";'
)
t.check(
	"strip_comments handles escaped quotes in strings",
	transform.strip_comments('val s = "esc \\" (* still string";')
		== 'val s = "esc \\" (* still string";'
)
t.check(
	"strip_comments on comment-only text yields whitespace",
	transform.strip_comments("(* just\na note *)"):find("%S") == nil
)
local _, unclosed = transform.strip_comments("val a = 1;\n(* a (* b *)\nQED")
t.check("strip_comments reports unclosed comment line", unclosed == 2)
local _, balanced = transform.strip_comments("(* a (* b *) c *)\nval x = 1;")
t.check("strip_comments balanced reports nil", balanced == nil)
local _, reopened =
	transform.strip_comments("(* one *)\nval a = 1;\n\n(* two (* deep *)")
t.check("unclosed line is the outermost open, not the first ever", reopened == 4)

-- send() guard: incomplete script-file blocks are refused with a warning
-- instead of wedging the REPL's filter at its '#' prompt
local repl_for_guard = require("hol4nvim.repl")
local saved_transport = repl_for_guard.config.transport
repl_for_guard.config.transport = "terminal" -- no session: nothing really sent
local notes = {}
local saved_notify = vim.notify
vim.notify = function(msg)
	table.insert(notes, msg)
end

repl_for_guard.send("Theorem foo:\n  T\nProof\n  rw[]")
t.check(
	"send refuses Theorem without QED",
	#notes > 0 and notes[#notes]:find("incomplete block") ~= nil
)

notes = {}
repl_for_guard.send("Definition bar:\n  bar = 1")
t.check(
	"send refuses Definition without End",
	#notes > 0 and notes[#notes]:find("incomplete block") ~= nil
)

notes = {}
repl_for_guard.send("Theorem foo:\n  T\nProof\n  rw[]\nQED;")
t.check(
	"complete Theorem passes the guard",
	#notes > 0 and notes[#notes]:find("incomplete block") == nil
)

notes = {}
repl_for_guard.send("Theorems = [foo_thm];") -- 'Theorems' is not the keyword
t.check(
	"guard ignores non-keyword lookalikes",
	#notes > 0 and notes[#notes]:find("incomplete block") == nil
)

-- a charwise selection sweeping onto the QED line but stopping at 'Q'
notes = {}
repl_for_guard.send("Theorem foo:\n  T\nProof\n  rw[]\nQ;")
t.check(
	"guard hints at truncated closer",
	#notes > 0 and notes[#notes]:find("stopped short") ~= nil
)

-- proof-manager control commands: literal sends, count semantics
local ctl_sent
local ctl_saved_send = repl_for_guard.send
repl_for_guard.send = function(text)
	ctl_sent = text
end
repl_for_guard.backup()
t.check("backup sends literal call", ctl_sent == "proofManagerLib.backup();")
repl_for_guard.backup(3)
t.check(
	"count repeats backup (3\\b)",
	ctl_sent
		== "proofManagerLib.backup(); proofManagerLib.backup();"
			.. " proofManagerLib.backup();"
)
repl_for_guard.drop(2)
t.check(
	"count repeats drop",
	ctl_sent == "proofManagerLib.drop(); proofManagerLib.drop();"
)
repl_for_guard.rotate(4)
t.check("count is rotate's argument", ctl_sent == "proofManagerLib.rotate(4);")
repl_for_guard.p()
t.check("p sends literal call", ctl_sent == "proofManagerLib.p();")
repl_for_guard.save()
t.check("save sends literal call", ctl_sent == "proofManagerLib.save();")
repl_for_guard.restart()
t.check("restart sends literal call", ctl_sent == "proofManagerLib.restart();")
repl_for_guard.restore()
t.check("restore sends literal call", ctl_sent == "proofManagerLib.restore();")
repl_for_guard.toggle_types()
t.check(
	"toggle_types sends literal call",
	ctl_sent == "Globals.show_types := not (!Globals.show_types);"
)
repl_for_guard.toggle_unicode()
t.check(
	"toggle_unicode sends literal call",
	ctl_sent
		== 'Feedback.set_trace "PP.avoid_unicode"'
			.. ' (1 - Feedback.current_trace "PP.avoid_unicode");'
)
repl_for_guard.send = ctl_saved_send

-- interrupt with no session and no fifo reader: warns, does not write.
-- hol_cmd is pinned to a nonexistent binary so fifo.path cannot derive this
-- machine's real HOL root (and reach a live global fifo) via $PATH.
do
	local save_fifo_env2, save_holdir2 = vim.env.VIMHOL_FIFO, vim.env.HOLDIR
	local save_hol_cmd2 = repl_for_guard.config.hol_cmd
	vim.env.VIMHOL_FIFO, vim.env.HOLDIR = nil, nil
	repl_for_guard.config.hol_cmd = "/nonexistent/hol"
	notes = {}
	repl_for_guard.interrupt()
	t.check(
		"interrupt without session warns",
		#notes > 0 and notes[#notes]:find("no HOL session") ~= nil
	)
	vim.env.VIMHOL_FIFO, vim.env.HOLDIR = save_fifo_env2, save_holdir2
	repl_for_guard.config.hol_cmd = save_hol_cmd2
end

vim.notify = saved_notify
repl_for_guard.config.transport = saved_transport

-- holdir() resolution priority: config.holdir > derived from the hol
-- binary (through $PATH and symlinks, requiring bin/ + a tools/ sibling)
-- > $HOLDIR. Uses a fake HOL tree so the tier stays HOL-free.
local repl = require("hol4nvim.repl")
local fifo = require("hol4nvim.fifo")
local save_fifo_env, save_holdir = vim.env.VIMHOL_FIFO, vim.env.HOLDIR
local save_hol_cmd, save_cfg_holdir = repl.config.hol_cmd, repl.config.holdir
local save_cfg_vimhol = repl.config.vimhol

local fake_root = vim.fn.tempname()
vim.fn.mkdir(fake_root .. "/bin", "p")
vim.fn.mkdir(fake_root .. "/tools", "p")
vim.fn.writefile({ "#!/bin/sh" }, fake_root .. "/bin/hol")
vim.uv.fs_chmod(fake_root .. "/bin/hol", 493) -- 0755
local real_root = vim.uv.fs_realpath(fake_root)

repl.config.hol_cmd = fake_root .. "/bin/hol"
repl.config.holdir = "/explicit/holdir"
vim.env.HOLDIR = "/env/holdir"
t.check("holdir prefers config.holdir", repl.holdir() == "/explicit/holdir")

repl.config.holdir = nil
t.check(
	"holdir derives from the hol binary over $HOLDIR",
	repl.holdir() == real_root
)

local link_dir = vim.fn.tempname()
vim.fn.mkdir(link_dir, "p")
vim.uv.fs_symlink(fake_root .. "/bin/hol", link_dir .. "/hol")
repl.config.hol_cmd = link_dir .. "/hol"
t.check("holdir resolves a symlinked hol", repl.holdir() == real_root)

local flat_dir = vim.fn.tempname() -- hol not under a bin/: no derivation
vim.fn.mkdir(flat_dir, "p")
vim.fn.writefile({ "#!/bin/sh" }, flat_dir .. "/hol")
vim.uv.fs_chmod(flat_dir .. "/hol", 493)
repl.config.hol_cmd = flat_dir .. "/hol"
t.check(
	"holdir falls back to $HOLDIR when hol is not under bin/",
	repl.holdir() == "/env/holdir"
)

local bare_root = vim.fn.tempname() -- bin/hol but no tools/: not a HOL tree
vim.fn.mkdir(bare_root .. "/bin", "p")
vim.fn.writefile({ "#!/bin/sh" }, bare_root .. "/bin/hol")
vim.uv.fs_chmod(bare_root .. "/bin/hol", 493)
repl.config.hol_cmd = bare_root .. "/bin/hol"
t.check(
	"holdir falls back to $HOLDIR without a tools/ sibling",
	repl.holdir() == "/env/holdir"
)

repl.config.hol_cmd = "/nonexistent/hol"
vim.env.HOLDIR = nil
t.check("holdir nil when nothing resolves", repl.holdir() == nil)

-- vimhol_sml() (7a bootstrap discovery): false disables, a string is an
-- explicit file, true discovers under holdir() (current then pre-rename
-- layout), nil when nothing resolves
repl.config.vimhol = false
t.check("vimhol_sml nil when disabled", repl.vimhol_sml() == nil)

repl.config.vimhol = "/my/vimhol.sml"
t.check("vimhol_sml honours explicit path", repl.vimhol_sml() == "/my/vimhol.sml")

repl.config.vimhol = true
vim.fn.mkdir(fake_root .. "/tools/editor-modes/vim", "p")
vim.fn.writefile({ "(* fake *)" }, fake_root .. "/tools/editor-modes/vim/vimhol.sml")
repl.config.hol_cmd = fake_root .. "/bin/hol"
t.check(
	"vimhol_sml discovered under holdir",
	repl.vimhol_sml() == real_root .. "/tools/editor-modes/vim/vimhol.sml"
)

local old_root = vim.fn.tempname() -- pre-rename tree: tools/vim/vimhol.sml
vim.fn.mkdir(old_root .. "/bin", "p")
vim.fn.mkdir(old_root .. "/tools/vim", "p")
vim.fn.writefile({ "#!/bin/sh" }, old_root .. "/bin/hol")
vim.uv.fs_chmod(old_root .. "/bin/hol", 493)
vim.fn.writefile({ "(* fake *)" }, old_root .. "/tools/vim/vimhol.sml")
repl.config.hol_cmd = old_root .. "/bin/hol"
t.check(
	"vimhol_sml falls back to the pre-rename layout",
	repl.vimhol_sml() == vim.uv.fs_realpath(old_root) .. "/tools/vim/vimhol.sml"
)

repl.config.hol_cmd = "/nonexistent/hol"
t.check("vimhol_sml nil when nothing resolves", repl.vimhol_sml() == nil)

-- fifo.path resolution priority: config > $VIMHOL_FIFO > the holdir default
repl.config.fifo = "/explicit/fifo"
vim.env.VIMHOL_FIFO = "/env/fifo"
vim.env.HOLDIR = "/holdir"
t.check("fifo.path prefers config", fifo.path() == "/explicit/fifo")

repl.config.fifo = nil
t.check("fifo.path falls back to $VIMHOL_FIFO", fifo.path() == "/env/fifo")

vim.env.VIMHOL_FIFO = nil
t.check(
	"fifo.path falls back to the resolved holdir ($HOLDIR here)",
	fifo.path() == "/holdir/tools/editor-modes/vim/fifo"
)

repl.config.hol_cmd = fake_root .. "/bin/hol"
t.check(
	"fifo.path uses the derived holdir over $HOLDIR",
	fifo.path() == real_root .. "/tools/editor-modes/vim/fifo"
)

repl.config.hol_cmd = "/nonexistent/hol"
vim.env.HOLDIR = nil
t.check("fifo.path nil when nothing set", fifo.path() == nil)

-- external_recipe() (7c): actionable no-reader guidance. Creates the fifo
-- so the pasted recipe finds a working pipe; names the env line and the
-- guarded use (or a placeholder when vimhol.sml is unresolvable).
t.check(
	"recipe explains when no fifo path resolves",
	repl.external_recipe():find("set config.fifo or config.holdir") ~= nil
)

local recipe_fifo = vim.fn.tempname()
repl.config.fifo = recipe_fifo
repl.config.vimhol = "/my/vimhol.sml"
local recipe = repl.external_recipe()
t.check(
	"recipe names the fifo env line",
	recipe:find("VIMHOL_FIFO='" .. recipe_fifo .. "' hol", 1, true) ~= nil
)
t.check(
	"recipe pastes the guarded use",
	recipe:find('NONE => use "/my/vimhol.sml"', 1, true) ~= nil
)
local recipe_stat = vim.uv.fs_stat(recipe_fifo)
t.check(
	"recipe created the fifo",
	recipe_stat ~= nil and recipe_stat.type == "fifo"
)
t.check("fifo.ensure tolerates an existing fifo", fifo.ensure(recipe_fifo))

repl.config.vimhol = false
t.check(
	"recipe falls back to a use placeholder",
	repl.external_recipe():find("<HOLDIR>", 1, true) ~= nil
)

local not_a_fifo = vim.fn.tempname()
vim.fn.writefile({ "" }, not_a_fifo)
repl.config.fifo = not_a_fifo
t.check(
	"recipe flags a non-fifo in the way",
	repl.external_recipe():find("is not a fifo") ~= nil
)

-- send() with no session and no reader warns with the recipe (the created
-- fifo above has no reader, so ready() is false and nothing blocks)
do
	repl.config.fifo = recipe_fifo
	local recipe_notify, warned = vim.notify, nil
	vim.notify = function(msg)
		warned = msg
	end
	repl.send("val recipe_probe = 1;")
	vim.notify = recipe_notify
	t.check(
		"no-reader send warns with the recipe",
		warned ~= nil
			and warned:find("no fifo reader") ~= nil
			and warned:find("VIMHOL_FIFO", 1, true) ~= nil
	)
end
repl.config.fifo = nil

vim.env.VIMHOL_FIFO, vim.env.HOLDIR = save_fifo_env, save_holdir
repl.config.hol_cmd, repl.config.holdir = save_hol_cmd, save_cfg_holdir
repl.config.vimhol = save_cfg_vimhol

-- setup() expands "~" in path-like options (a spec written on another
-- machine says hol_cmd = "~/HOL/bin/hol"; jobstart takes ~ literally)
do
	local save = vim.deepcopy(repl.config)
	require("hol4nvim").setup({
		hol_cmd = "~/HOL/bin/hol",
		holdir = "~/HOL/",
		fifo = "~/HOL/tools/editor-modes/vim/fifo",
		vimhol = true,
	})
	local home = vim.uv.os_homedir()
	t.check("setup expands ~ in hol_cmd", repl.config.hol_cmd == home .. "/HOL/bin/hol")
	t.check(
		"setup expands ~ and trims trailing / in holdir",
		repl.config.holdir == home .. "/HOL"
	)
	t.check(
		"setup expands ~ in fifo",
		repl.config.fifo == home .. "/HOL/tools/editor-modes/vim/fifo"
	)
	t.check("setup leaves boolean vimhol alone", repl.config.vimhol == true)
	repl.config = save
end

-- holdir alone must configure the binary too: which_hol falls back to
-- <config.holdir>/bin/hol ahead of $HOLDIR / $PATH
do
	local save_cmd, save_dir, save_env = repl.config.hol_cmd, repl.config.holdir, vim.env.HOLDIR
	repl.config.hol_cmd, repl.config.holdir, vim.env.HOLDIR = nil, fake_root, nil
	t.check(
		"which_hol derives bin/hol from config.holdir",
		repl.which_hol() == fake_root .. "/bin/hol"
	)
	repl.config.hol_cmd, repl.config.holdir, vim.env.HOLDIR = save_cmd, save_dir, save_env
end

-- which_hol tolerates hol_cmd naming a directory (bin/ or the HOL root)
do
	local save = repl.config.hol_cmd
	repl.config.hol_cmd = fake_root .. "/bin"
	t.check(
		"which_hol resolves hol inside a bin/ directory hol_cmd",
		repl.which_hol() == fake_root .. "/bin/hol"
	)
	repl.config.hol_cmd = fake_root
	t.check(
		"which_hol resolves bin/hol inside a HOL-root hol_cmd",
		repl.which_hol() == fake_root .. "/bin/hol"
	)
	repl.config.hol_cmd = save
end

-- ftplugin: buffer-local keymaps appear on a hol4script buffer, under
-- whatever <localleader> init.lua sets (do not assume backslash)
vim.cmd("enew")
vim.bo.filetype = "hol4script"
local ll = vim.g.maplocalleader or "\\"
local function has_buf_map(mode, suffix)
	local m = vim.fn.maparg(ll .. suffix, mode, false, true)
	return not vim.tbl_isempty(m) and m.buffer == 1
end
for _, spec in ipairs({
	{ "n", "x" },
	{ "n", "X" },
	{ "n", "s" },
	{ "x", "s" },
	{ "n", "w" },
	{ "n", "u" },
	{ "x", "u" },
	{ "n", "!" },
	{ "x", "!" },
	{ "n", "e" },
	{ "x", "e" },
	{ "n", "g" },
	{ "x", "g" },
	{ "n", "G" },
	{ "x", "G" },
	{ "n", "S" },
	{ "n", "F" },
	{ "n", "P" },
	{ "n", "l" },
	{ "x", "l" },
	{ "n", "b" },
	{ "n", "B" },
	{ "n", "v" },
	{ "n", "d" },
	{ "n", "p" },
	{ "n", "r" },
	{ "n", "R" },
	{ "n", "c" },
	{ "n", "t" },
	{ "n", "T" },
	{ "n", "a" },
	{ "n", "y" },
	{ "n", "n" },
	{ "n", "h" },
	{ "x", "h" },
}) do
	t.check(
		"keymap " .. spec[1] .. " <localleader>" .. spec[2],
		has_buf_map(spec[1], spec[2])
	)
end

-- comment-only sends: notified, nothing sent (uses the scratch buffer above)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "(* just a comment *)" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
repl_for_guard.config.transport = "terminal"
notes = {}
vim.notify = function(msg)
	table.insert(notes, msg)
end
repl_for_guard.send_line()
t.check(
	"comment-only line is not sent",
	#notes > 0 and notes[#notes]:find("nothing to send") ~= nil
)

-- an unclosed comment inside a theorem block: refused with the comment
-- diagnosis, NOT a confusing missing-QED warning
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"Theorem tricky:",
	"  T",
	"Proof",
	"  (* outer (* inner *)",
	"  rw[]",
	"QED",
})
notes = {}
vim.cmd("normal! ggVG")
repl_for_guard.send_visual()
t.check(
	"unclosed comment in block is diagnosed",
	#notes > 0 and notes[#notes]:find("unclosed comment") ~= nil
)
t.check(
	"unclosed comment names its line",
	#notes > 0 and notes[#notes]:find("line 4") ~= nil
)

-- send_document: whole buffer, open declarations dropped (single- and
-- multi-line), comments stripped; capture what reaches send()
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"open HolKernel boolLib;",
	"val a = 1;",
	"open arithmeticTheory",
	"     realTheory;",
	"(* a comment mentioning Theorem foo: with no QED *)",
	"val b = 2;",
})
local sent = nil
local saved_send = repl_for_guard.send
repl_for_guard.send = function(text)
	sent = text
end
repl_for_guard.send_document()
repl_for_guard.send = saved_send
t.check("send_document sends the code", sent ~= nil and sent:find("val a = 1;") ~= nil and sent:find("val b = 2;") ~= nil)
t.check(
	"send_document drops single-line open",
	sent ~= nil and sent:find("HolKernel") == nil
)
t.check(
	"send_document drops multi-line open",
	sent ~= nil
		and sent:find("arithmeticTheory") == nil
		and sent:find("realTheory") == nil
)
t.check(
	"send_document strips comments",
	sent ~= nil and sent:find("Theorem foo") == nil
)

vim.notify = saved_notify
repl_for_guard.config.transport = saved_transport

-- selection helpers (\t \T \a) on a scratch hol4script buffer
vim.cmd("enew")
vim.bo.filetype = "hol4script"
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"val g = `x + y`;",
	"``a /\\ b``",
	"Theorem sel_test:",
	"  !x. x = x",
	"Proof",
	"  rw[]",
	"QED",
})
local select = require("hol4nvim.select")

vim.api.nvim_win_set_cursor(0, { 1, 10 }) -- on the + inside `x + y`
select.term()
t.check("select.term enters visual", vim.fn.mode() == "v")
t.check(
	"select.term spans the backticks",
	vim.fn.getpos("v")[3] == 9 and vim.fn.getpos(".")[3] == 15
)
vim.cmd("normal! \27")

vim.api.nvim_win_set_cursor(0, { 2, 4 }) -- inside ``a /\ b``
select.quoted_term()
t.check(
	"select.quoted_term spans the double backticks",
	vim.fn.mode() == "v"
		and vim.fn.getpos("v")[3] == 1
		and vim.fn.getpos(".")[3] == 10
)
vim.cmd("normal! \27")

vim.api.nvim_win_set_cursor(0, { 6, 0 }) -- inside the proof
select.theorem()
t.check(
	"select.theorem is linewise statement+Proof",
	vim.fn.mode() == "V"
		and vim.fn.getpos(".")[2] == 4 -- statement line (Theorem line dropped)
		and vim.fn.getpos("v")[2] == 5 -- the Proof line
)
vim.cmd("normal! \27")

-- holabs abbreviations: opt-in, buffer-local, reversible
local saved_abbrev = repl_for_guard.config.abbreviations
repl_for_guard.config.abbreviations = true
vim.cmd("enew")
vim.bo.filetype = "hol4script"
local ab = vim.fn.maparg("IN", "i", true, true)
t.check(
	"abbrev IN registered buffer-locally",
	not vim.tbl_isempty(ab) and ab.buffer == 1
)
vim.api.nvim_feedkeys(
	vim.api.nvim_replace_termcodes("ip /\\ q <Esc>", true, false, true),
	"x",
	false
)
t.check(
	"abbrev /\\ expands to ∧ while typing",
	vim.api.nvim_get_current_line() == "p ∧ q "
)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "∀x. x ∈ s ⇒ x ≤ y ∧ T" })
require("hol4nvim.abbrev").unabbrev(1, 1)
t.check(
	"unabbrev restores ASCII",
	vim.api.nvim_get_current_line() == "!x. x IN s ==> x <= y /\\ T"
)
-- with the option off, a fresh buffer gets no abbreviations
repl_for_guard.config.abbreviations = false
vim.cmd("enew")
vim.bo.filetype = "hol4script"
t.check(
	"abbreviations respect config off",
	vim.tbl_isempty(vim.fn.maparg("IN", "i", true, true))
)
repl_for_guard.config.abbreviations = saved_abbrev

-- 5a regex syntax: syntax/hol4script.vim loads for the filetype and
-- colours the script-level structure
vim.cmd("syntax enable")
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, {
	"Theorem foo:",
	"  T",
	"Proof",
	"  cheat",
	"QED",
	"(* note *)",
})
vim.bo.filetype = "hol4script"
local function syn_at(l, c)
	return vim.fn.synIDattr(vim.fn.synID(l, c, false), "name")
end
t.check("syntax file loaded", vim.b.current_syntax == "hol4script")
t.check("Theorem keyword highlighted", syn_at(1, 1) == "MLKeyword")
t.check("Proof keyword highlighted", syn_at(3, 1) == "MLKeyword")
t.check("cheat flagged as error", syn_at(4, 3) == "MLCheat")
t.check("QED highlighted", syn_at(5, 1) == "HOLQED")
t.check("comment highlighted", syn_at(6, 3) == "MLComment")

t.finish()
