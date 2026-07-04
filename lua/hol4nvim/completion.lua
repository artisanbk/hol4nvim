--[[
  hol4nvim.completion -- insert-mode completion of HOL tactics and the live
  theory database's theorem names, delivered as an nvim-cmp source.

  Two vocabularies feed one source:
    - M.TACTICS: a curated, static list of common HOL tactics/tacticals,
      available offline with no REPL running;
    - M.cache.theorems: theorem names snapshotted from the running session's
      DB.listDB(), refreshed on demand.

  The plugin's transport is one-way (see repl.send): there is no channel to
  read HOL's answer per keystroke. So theorem names are not queried live;
  M.refresh() sends an SML enumeration that writes "name<TAB>theory" lines to a
  temp file (the same round-trip hol4nvim.search uses), then polls that file
  asynchronously and updates the cache. Refreshes fire off the User autocmds
  repl emits (HolReplStarted / HolLoaded), lazily on first completion, and via
  :HolCompletionRefresh.

  The command is a SINGLE line (no embedded newlines): send() routes multi-line
  batches through the Vimhol pipe, which may not be attached yet in the first
  moments after a REPL starts -- a one-liner goes straight to the pty and can
  never wedge the filter mid-construct.

  Delivery is nvim-cmp (M.register). The completion.enabled flag -- flipped by
  :HolCompletionToggle -- gates the source's is_available, so completion can be
  switched off without disturbing the user's cmp config.
--]]

local M = {}

-- Folded from `require("hol4nvim").setup({ completion = {...} })`.
M.config = {
	enabled = true, -- master switch; :HolCompletionToggle flips this
	auto_setup = true, -- register + inject the source into hol4script's cmp sources
	tactics = true, -- offer the static tactic vocabulary
	theorems = true, -- offer live theorem names from the session's DB
}

-- LSP CompletionItemKind numerals. cmp reads item.kind as a plain number, so
-- the core tags items without ever requiring cmp.
local KIND_FUNCTION = 3
local KIND_CONSTANT = 21

M.SENTINEL = "===HOLCOMPLETE_DONE==="

--[[
  Static tactic / tactical vocabulary (Tier A). A curated slice of the tactics
  a HOL proof reaches for constantly -- not the whole of the tactic libraries.
  Deliberately biased toward the modern (lower-case, Q.-free) surface: rw/simp,
  the drule family, qexists_tac, etc. Extend freely; order is irrelevant (cmp
  sorts), duplicates are harmless.
--]]
M.TACTICS = {
	-- structural / introduction
	"strip_tac", "rpt", "gen_tac", "conj_tac", "disj1_tac", "disj2_tac",
	"eq_tac", "EQ_TAC", "impl_tac", "reverse", "wlog_tac",
	-- induction / case analysis
	"Induct", "Induct_on", "Cases", "Cases_on", "namedCases_on",
	"completeInduct_on", "measureInduct_on", "recInduct", "ho_match_mp_tac",
	-- rewriting / simplification
	"rw", "srw_tac", "simp", "fs", "rfs", "gs", "gvs", "gnvs",
	"rewrite_tac", "asm_rewrite_tac", "once_rewrite_tac", "pure_rewrite_tac",
	"simp_tac", "asm_simp_tac", "full_simp_tac", "rw_tac", "csimp",
	"DEP_REWRITE_TAC", "SUBST_ALL_TAC", "AP_TERM_TAC", "AP_THM_TAC",
	-- automation
	"metis_tac", "prove_tac", "decide_tac", "DECIDE", "ARITH_TAC",
	"intLib.ARITH_TAC", "cooper_tac", "fcp_tac", "blastLib.BBLAST_TAC",
	"CCONTR_TAC", "spose_not_then",
	-- resolution / matching
	"irule", "irule_at", "drule", "dxrule", "rev_drule", "drule_then",
	"drule_all", "drule_at", "imp_res_tac", "res_tac", "match_mp_tac",
	"mp_tac", "assume_tac", "strip_assume_tac", "disch_tac", "disch_then",
	-- assumption manipulation
	"pop_assum", "first_assum", "first_x_assum", "last_assum", "last_x_assum",
	"qpat_assum", "qpat_x_assum", "goal_assum", "PRED_ASSUM",
	-- Q-flavoured witnesses / naming
	"qexists_tac", "qexistsl_tac", "qexists", "exists_tac", "qrefine",
	"qspec_then", "qspecl_then", "qabbrev_tac", "qunabbrev_tac",
	"qmatch_goalsub_abbrev_tac", "qmatch_asmsub_abbrev_tac",
	"qmatch_rename_tac", "qmatch_goalsub_rename_tac", "rename1", "rename",
	"qid_spec_tac", "qx_gen_tac", "qx_choose_then", "X_GEN_TAC",
	-- subgoals / structuring
	"by", "suffices_by", "sg", "subgoal", "kall_tac", "all_tac", "NO_TAC",
	"ntac", "cheat", "Cong",
	-- tacticals
	"THEN", "THENL", "THEN1", "ORELSE", "TRY", "REPEAT", "FIRST", "EVERY",
	"MAP_EVERY", "MAP_FIRST", "CHANGED_TAC", "REVERSE", "map_every",
	-- theorem-valued helpers commonly written inline
	"GSYM", "SYM", "MATCH_MP", "SPEC", "SPECL", "SPEC_ALL", "GEN", "GENL",
	"UNDISCH", "CONJUNCT1", "CONJUNCT2", "iffLR", "iffRL", "cj", "Once",
	"Ntimes", "AllCaseEqs", "CaseEq", "oneline",
	-- simpsets (frequently named in simp/fs modifier lists)
	"bool_ss", "arith_ss", "std_ss", "list_ss", "pure_ss", "srw_ss",
}

-- Escape a Lua string into an SML string literal (shared shape with search).
local function sml_string(s)
	return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--[[
  SML to enumerate every public theorem name in the session and write
  "name<TAB>theory" lines to `outfile`, ending with the sentinel. Kept on ONE
  line (join with " ") so it goes straight to the pty and never needs the pipe.
  Private theorems are filtered out (thminfo.private) -- they cannot be
  referenced by name from another context, so completing them would mislead.
  Pure/deterministic so it can be unit-tested without HOL.
--]]
M.enumerate_cmd = function(outfile)
	local out = sml_string(outfile)
	return table.concat({
		"val () = (",
		"(let val hnv_data = DB.listDB ()",
		"fun hnv_pub (_,(_,{private=hnv_p,...})) = not hnv_p",
		'fun hnv_line ((hnv_thy,hnv_nm),_) = hnv_nm ^ "\\t" ^ hnv_thy',
		"val hnv_names = List.map hnv_line (List.filter hnv_pub hnv_data)",
		"val hnv_os = TextIO.openOut " .. out,
		"in",
		'List.app (fn hnv_s => TextIO.output(hnv_os, hnv_s ^ "\\n")) hnv_names;',
		'TextIO.output(hnv_os, "'
			.. M.SENTINEL
			.. ' (" ^ Int.toString (length hnv_names) ^ " names)\\n");',
		"TextIO.closeOut hnv_os end)",
		"handle hnv_e =>",
		"(let val hnv_os = TextIO.openOut " .. out,
		'in TextIO.output(hnv_os, "'
			.. M.SENTINEL
			.. ' (error: " ^ General.exnMessage hnv_e ^ ")\\n"); TextIO.closeOut hnv_os end)',
		");",
	}, " ")
end

--[[
  Parse the enumeration file. Returns a de-duplicated { {label, detail}, ... }
  list (detail = the theory a name first appeared in) once the sentinel is
  present, or nil while it is not (the poll's "not done yet" signal). Pure.
--]]
M.parse_names = function(lines)
	local done, items, seen = false, {}, {}
	for _, line in ipairs(lines) do
		if line:find(M.SENTINEL, 1, true) then
			done = true
		elseif line ~= "" then
			local name, thy = line:match("^([^\t]+)\t(.*)$")
			name = name or line
			if not seen[name] then
				seen[name] = true
				items[#items + 1] = { label = name, detail = thy }
			end
		end
	end
	if not done then
		return nil
	end
	return items
end

-- Snapshot of the last successful enumeration.
M.cache = { theorems = {}, loaded = false }

-- A live transport must exist or send() only warns and the poll times out.
-- Mirror send()'s routing decision (same predicate as search).
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

-- Poll `outfile` off the UI thread until the sentinel lands or `timeout` ms
-- elapse; call on_done(items) or on_done(nil) on timeout. Background refresh
-- must not block the editor, so this uses a libuv timer, not vim.wait.
local function poll(outfile, timeout, on_done)
	local timer = vim.uv.new_timer()
	local waited, step = 0, 150
	timer:start(
		step,
		step,
		vim.schedule_wrap(function()
			waited = waited + step
			local items
			if vim.fn.filereadable(outfile) == 1 then
				items = M.parse_names(vim.fn.readfile(outfile))
			end
			if items ~= nil then
				timer:stop()
				timer:close()
				on_done(items)
			elseif waited >= timeout then
				timer:stop()
				timer:close()
				on_done(nil)
			end
		end)
	)
end

--[[
  Refresh the theorem cache from the live session. Asynchronous: sends the
  enumeration, polls the temp file, then invokes cb(ok, info) -- info is the
  theorem count on success or a reason string on failure. Safe to call with no
  session (cb(false, ...) immediately).
--]]
M.refresh = function(cb)
	cb = cb or function() end
	if not M.config.theorems then
		cb(false, "theorem completion disabled")
		return
	end
	if not transport_ready() then
		cb(false, "no HOL session")
		return
	end
	local outfile = vim.fn.tempname()
	pcall(os.remove, outfile)
	require("hol4nvim.repl").send(M.enumerate_cmd(outfile))
	poll(outfile, 15000, function(items)
		pcall(os.remove, outfile)
		if items == nil then
			cb(false, "timed out (no response from the REPL)")
			return
		end
		M.cache.theorems = items
		M.cache.loaded = true
		cb(true, #items)
	end)
end

-- Debounced refresh, coalescing the burst of events a session start / load
-- produces into one enumeration. Skips silently when theorem completion is off.
local refresh_pending = false
M.schedule_refresh = function(delay)
	if not M.config.theorems or refresh_pending then
		return
	end
	refresh_pending = true
	vim.defer_fn(function()
		refresh_pending = false
		M.refresh(function() end)
	end, delay or 800)
end

-- Tactic items are static; build them once.
local tactic_items
M.tactic_items = function()
	if not tactic_items then
		tactic_items = {}
		for _, t in ipairs(M.TACTICS) do
			tactic_items[#tactic_items + 1] =
				{ label = t, kind = KIND_FUNCTION, detail = "HOL tactic" }
		end
	end
	return tactic_items
end

--- The full completion item list: static tactics (if enabled) plus cached
--- theorem names (if enabled), each cmp-shaped with a kind and a detail.
M.items = function()
	local out = {}
	if M.config.tactics then
		vim.list_extend(out, M.tactic_items())
	end
	if M.config.theorems then
		for _, it in ipairs(M.cache.theorems) do
			out[#out + 1] = {
				label = it.label,
				kind = KIND_CONSTANT,
				detail = it.detail and (it.detail .. "Theory") or "theorem",
			}
		end
	end
	return out
end

M.is_enabled = function()
	return M.config.enabled ~= false
end

--- Flip completion on/off at runtime (bound to :HolCompletionToggle). Gates the
--- source's is_available, so no cmp reconfiguration is needed.
M.toggle = function()
	M.config.enabled = not M.is_enabled()
	vim.notify(
		"hol4nvim: completion " .. (M.config.enabled and "enabled" or "disabled"),
		vim.log.levels.INFO
	)
	return M.config.enabled
end

--[[
  Register the "hol4nvim" nvim-cmp source and, when auto_setup is on, prepend
  it to the hol4script filetype's sources (merged with whatever the user
  already configured, deduplicated) so it works out of the box. No-ops without
  nvim-cmp installed. Returns true if the source was registered.
--]]
M.register = function()
	local ok, cmp = pcall(require, "cmp")
	if not ok then
		return false
	end
	cmp.register_source("hol4nvim", require("hol4nvim.cmp").new())
	if M.config.auto_setup then
		pcall(function()
			local existing = (cmp.get_config() or {}).sources or {}
			local merged = { { name = "hol4nvim" } }
			for _, s in ipairs(existing) do
				if not (type(s) == "table" and s.name == "hol4nvim") then
					merged[#merged + 1] = s
				end
			end
			cmp.setup.filetype("hol4script", { sources = merged })
		end)
	end
	return true
end

--[[
  Wire up completion: refresh the cache when a REPL starts or dependencies are
  loaded (repl fires these User autocmds so it need not depend on this module),
  and register the cmp source. Called from hol4nvim.setup().
--]]
M.setup = function()
	local grp = vim.api.nvim_create_augroup("hol4nvim.completion", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = grp,
		pattern = { "HolReplStarted", "HolLoaded" },
		callback = function()
			M.schedule_refresh()
		end,
	})
	M.register()
end

return M
