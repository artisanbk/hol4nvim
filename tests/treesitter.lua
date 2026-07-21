--[[
  Tree-sitter tier (Phase 5b): HOL-free checks that the holscript parser
  loads off the plugin's own rtp, attaches to hol4script buffers via the
  ftplugin, produces the expected script-level trees, and that the shipped
  queries compile and capture sensibly.
      make test-ts   (builds parser/holscript.so first; needs only cc)
  If the parser is not built, the tier skips with a notice rather than
  failing: the regex tier is the documented fallback.
--]]

local t = dofile("tests/util.lua")

-- language.add returns nil+err rather than throwing on newer Neovim, so
-- probe by actually constructing a parser
if not pcall(vim.treesitter.get_string_parser, "", "holscript") then
	io.write("SKIP tree-sitter tier: parser/holscript.so not built " ..
		"(run `make parsers`)\n")
	os.exit(0)
end

-- ftplugin integration: opening a *Script.sml attaches the TS highlighter
-- (which disables the regex tier for the buffer)
vim.cmd.edit("examples/TestScript.sml")
local buf = vim.api.nvim_get_current_buf()
t.check(
	"filetype is hol4script",
	vim.bo[buf].filetype == "hol4script"
)
t.check(
	"treesitter highlighter attached",
	vim.treesitter.highlighter.active[buf] ~= nil
)

-- whole-file parses of both examples are ERROR-free
local function root_of_buf()
	local parser = vim.treesitter.get_parser(0, "holscript")
	return parser:parse()[1]:root()
end
t.check("TestScript.sml parses without errors", not root_of_buf():has_error())
vim.cmd.edit("examples/WholeScript.sml")
t.check("WholeScript.sml parses without errors", not root_of_buf():has_error())

-- targeted snippets, parsed as strings
local function tree(src)
	local parser = vim.treesitter.get_string_parser(src, "holscript")
	return parser:parse()[1]:root(), parser
end

local function types(node)
	local out = {}
	for child in node:iter_children() do
		if child:named() then
			out[#out + 1] = child:type()
		end
	end
	return table.concat(out, " ")
end

local root = tree("Theorem foo:\n  T\nProof\n  simp []\nQED\n")
t.check("theorem parses", types(root) == "theorem")
t.check(
	"theorem structure",
	types(root:named_child(0)) == "identifier term tactics"
)

root = tree("  Theorem indented:\n    T\n  Proof\n    simp []\n  QED\n")
t.check(
	"indented theorem parses (regex tier could not)",
	types(root) == "theorem" and not root:has_error()
)

root = tree("val x = `a + b’;\n")
t.check(
	"mismatched quotation is flagged",
	types(root):find("quotation_mismatched") ~= nil
)

root = tree("(* a (* nested (* comment *) *) here *)\nval x = 1;\n")
t.check(
	"nested comment is one comment node",
	types(root) == "comment ml_chunk" and not root:has_error()
)

root = tree(
	"Definition d:\n  d x = x\nTermination\n  WF_REL_TAC `measure I`\nEnd\n"
)
t.check(
	"definition with Termination",
	types(root:named_child(0)) == "identifier term tactics"
		and not root:has_error()
)

root = tree(
	"Theory foo\nAncestors\n  list string\nLibs\n  monadsyntax\n\nval x = 1;\n"
)
t.check(
	"theory header parses",
	types(root) == "theory_header ml_chunk" and not root:has_error()
)

-- queries: all three compile; highlights captures land where expected
local highlights = vim.treesitter.query.get("holscript", "highlights")
t.check("highlights query loads", highlights ~= nil)
t.check(
	"folds query loads",
	select(1, pcall(vim.treesitter.query.get, "holscript", "folds"))
)
t.check(
	"injections query loads",
	select(1, pcall(vim.treesitter.query.get, "holscript", "injections"))
)

local src = "Theorem foo[simp]:\n  `T`\nProof\n  simp []\nQED\n"
local qroot, parser = tree(src)
local got = {}
if highlights then
	for id, node in highlights:iter_captures(qroot, src) do
		local text = vim.treesitter.get_node_text(node, src)
		got[highlights.captures[id] .. "=" .. text] = true
	end
end
t.check("Theorem captured as keyword", got["keyword=Theorem"] == true)
t.check("QED captured as keyword", got["keyword=QED"] == true)
t.check("name captured as function", got["function=foo"] == true)
t.check("attributes captured", got["attribute=[simp]"] == true)
t.check("quotation captured", got["string.special=`T`"] == true)
local _ = parser

-- New-style theory header: the keywords must not land in the same capture as
-- the names they introduce, or a colorscheme that colors @keyword and @module
-- alike makes "Ancestors" indistinguishable from the theories listed under it.
do
	local hsrc = "Theory pure_misc\nAncestors\n  string sptree\nLibs\n  stringLib\n"
	local hroot = tree(hsrc)
	local hgot = {}
	if highlights then
		for id, node in highlights:iter_captures(hroot, hsrc) do
			hgot[highlights.captures[id] .. "=" .. vim.treesitter.get_node_text(node, hsrc)] =
				true
		end
	end
	t.check("Theory captured as keyword.directive", hgot["keyword.directive=Theory"] == true)
	t.check("Ancestors captured as keyword.import", hgot["keyword.import=Ancestors"] == true)
	t.check("Libs captured as keyword.import", hgot["keyword.import=Libs"] == true)
	t.check("theory name still captured as module", hgot["module=pure_misc"] == true)
	t.check(
		"imported names still captured as module",
		hgot["module=string sptree"] == true and hgot["module=stringLib"] == true
	)
	-- The invariant the user actually sees: no header keyword shares a capture
	-- with the names beside it.
	t.check(
		"header keywords do not share the names' capture",
		hgot["module=Theory"] ~= true
			and hgot["module=Ancestors"] ~= true
			and hgot["module=Libs"] ~= true
			and hgot["keyword=Ancestors"] ~= true
	)
end

-- ---------------------------------------------------------------------------
-- Phase 5c: injections. Each opaque span from the skeleton grammar hands its
-- interior to a real grammar (sml / holterm). `make test-ts` builds every
-- parser under grammar/*/, so sml and holterm are present here.
-- ---------------------------------------------------------------------------
local function lang_ok(lang)
	return pcall(vim.treesitter.get_string_parser, "", lang)
end
t.check("sml parser available", lang_ok("sml"))
t.check("holterm parser available", lang_ok("holterm"))

-- Parse a holscript source WITH injections, return whether a child tree of
-- `lang` exists and the set of "capture=text" pairs from its highlights query.
local function inject(injsrc, lang)
	local p = vim.treesitter.get_string_parser(injsrc, "holscript")
	p:parse(true)
	local child = p:children()[lang]
	local caps = {}
	if child then
		child:parse(true)
		local hq = vim.treesitter.query.get(lang, "highlights")
		if hq then
			child:for_each_tree(function(tr)
				for id, node in hq:iter_captures(tr:root(), injsrc) do
					caps[hq.captures[id] .. "=" .. vim.treesitter.get_node_text(node, injsrc)] =
						true
				end
			end)
		end
	end
	return child ~= nil, caps
end

-- ml_chunk -> sml (plain ML between blocks)
local ok_ml, ml = inject("val f = fn x => x andalso T;\n", "sml")
t.check("ml_chunk injects sml", ok_ml)
t.check("sml keyword highlighted in ml_chunk", ml["keyword=andalso"] == true)

-- tactic_chunk -> sml (tactics are SML)
local ok_tac = inject(
	"Theorem a:\n  T\nProof\n  simp [] >> metis_tac []\nQED\n",
	"sml"
)
t.check("tactic_chunk injects sml", ok_tac)

-- term_chunk (Definition body) -> holterm
local ok_tm, tm = inject("Definition d:\n  d x = x + 1\nEnd\n", "holterm")
t.check("term_chunk injects holterm", ok_tm)
t.check("holterm operator highlighted in term_chunk", tm["operator=+"] == true)

-- quotation interior -> holterm, delimiters trimmed by #offset!
local ok_q, q = inject("val g = `!x. P x`;\n", "holterm")
t.check("quotation injects holterm", ok_q)
t.check("holterm binder highlighted in quotation", q["keyword.operator=!"] == true)
local backtick_leaked = false
for cap in pairs(q) do
	if cap:find("`", 1, true) then
		backtick_leaked = true
	end
end
t.check("quotation delimiter trimmed (no backtick reaches holterm)", not backtick_leaked)

-- unicode quotation (3-byte delimiters) also trims correctly
local ok_u, u = inject("val h = \u{2018}a ==> b\u{2019};\n", "holterm")
t.check("unicode quotation injects holterm", ok_u)
t.check("holterm operator highlighted in unicode quotation", u["operator===>"] == true)

t.check(
	"holterm highlights query loads",
	vim.treesitter.query.get("holterm", "highlights") ~= nil
)
t.check(
	"sml highlights query loads",
	vim.treesitter.query.get("sml", "highlights") ~= nil
)

t.finish()
