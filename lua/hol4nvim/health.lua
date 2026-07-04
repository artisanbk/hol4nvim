--[[
  hol4nvim.health -- :checkhealth hol4nvim.

  Reports every discovery step the plugin performs at runtime (hol binary,
  holdir, holdeptool, vimhol.sml, fifo transport, tree-sitter parsers) by
  RE-RUNNING the plugin's own resolvers, so the health report can never drift
  from real behaviour. On a failure it names the exact setup() option to set.

  It also flags the one configuration mistake that has actually bitten a user:
  a keymap `prefix` equal to the leader. When a longer global leader map shares
  the prefix, every hol map waits 'timeoutlen' before firing -- the 800ms lag
  on `hs`/`he` that looked like a REPL problem but was a mapping problem. See
  M.prefix_collisions, unit-tested directly.
--]]

local repl = require("hol4nvim.repl")
local fifo = require("hol4nvim.fifo")
local keymaps = require("hol4nvim.keymaps")

local M = {}

-- Resolve a prefix spec to the byte sequence the mapping actually binds:
-- <localleader>/<leader> follow maplocalleader/mapleader (default "\"), a
-- literal like " " passes through nvim_replace_termcodes (so "<Space>" works).
local function resolved_prefix(prefix)
	prefix = prefix or "<localleader>"
	local lower = prefix:lower()
	if lower == "<localleader>" then
		local l = vim.g.maplocalleader
		return (l ~= nil and l ~= "") and l or "\\"
	elseif lower == "<leader>" then
		local l = vim.g.mapleader
		return (l ~= nil and l ~= "") and l or "\\"
	end
	return vim.api.nvim_replace_termcodes(prefix, true, true, true)
end

--[[
  Pure collision core (unit-tested directly, no vim.health needed).
    prefix   : byte-form prefix (from resolved_prefix)
    suffixes : the raw hol map suffixes (keymaps.suffixes())
    maps     : byte-form lhs strings of the OTHER (global) maps to test against
  Returns { {hol=<lhs>, culprit=<lhs>}, ... } for every map that has a hol map
  lhs as a STRICT prefix -- exactly the maps that force a 'timeoutlen' wait on
  that hol map (Neovim cannot resolve `<pfx>s` while `<pfx>sx` is still a
  possible continuation).
--]]
M.prefix_collisions = function(prefix, suffixes, maps)
	local hol = {}
	for _, s in ipairs(suffixes) do
		hol[prefix .. vim.api.nvim_replace_termcodes(s, true, true, true)] = true
	end
	local out = {}
	for _, lhs in ipairs(maps) do
		for hlhs in pairs(hol) do
			if #lhs > #hlhs and lhs:sub(1, #hlhs) == hlhs then
				out[#out + 1] = { hol = hlhs, culprit = lhs }
				break
			end
		end
	end
	return out
end

-- Byte-form lhs of every global map in the modes hol binds (n/x/o).
local function global_map_lhs()
	local out = {}
	for _, mode in ipairs({ "n", "x", "o" }) do
		local ok, maps = pcall(vim.api.nvim_get_keymap, mode)
		if ok then
			for _, m in ipairs(maps) do
				out[#out + 1] = vim.api.nvim_replace_termcodes(m.lhs, true, true, true)
			end
		end
	end
	return out
end

M.check = function()
	local h = vim.health
	local cfg = repl.config

	-- hol binary ------------------------------------------------------------
	h.start("hol4nvim: hol binary")
	local hol = repl.which_hol()
	if hol ~= "" and vim.fn.executable(hol) == 1 then
		h.ok("hol: " .. vim.fn.exepath(hol))
	elseif hol ~= "" then
		h.error("hol resolved to `" .. hol .. "` but it is not executable", {
			"set config.hol_cmd to the hol binary (a bin/ dir or the HOL root works too)",
			"or set config.holdir to your HOL installation root",
		})
	else
		h.error("no hol binary found", {
			"set config.hol_cmd to the hol binary, or config.holdir to the HOL root",
			"(otherwise: .HOLMK/lastmaker, then $HOLDIR/bin/hol, then hol on $PATH)",
		})
	end

	-- holdir ----------------------------------------------------------------
	h.start("hol4nvim: HOL installation root")
	local holdir = repl.holdir()
	if not holdir then
		h.warn("holdir could not be resolved", {
			"only hl (load deps), the default fifo path, and vimhol auto-load need it",
			"set config.holdir if you use those",
		})
	elseif cfg.holdir and cfg.holdir ~= "" then
		h.ok("holdir: " .. holdir .. " (from config.holdir)")
	elseif vim.env.HOLDIR and vim.env.HOLDIR ~= "" and holdir == vim.env.HOLDIR then
		h.warn("holdir: " .. holdir .. " (from $HOLDIR)", {
			"works, but $HOLDIR is the last-resort fallback",
			"set config.holdir to make setup independent of the environment",
		})
	else
		h.ok("holdir: " .. holdir .. " (derived from the hol binary)")
	end

	-- holdeptool (hl) -------------------------------------------------------
	h.start("hol4nvim: holdeptool (hl)")
	local tool = repl.holdeptool()
	if tool ~= "" then
		h.ok("holdeptool: " .. tool)
	else
		h.warn("holdeptool.exe not found next to hol or under holdir/bin", {
			"only hl (load deps) needs it; build HOL's holdeptool or set config.holdir",
		})
	end

	-- vimhol.sml (hx bootstrap) --------------------------------------------
	h.start("hol4nvim: vimhol auto-bootstrap (hx)")
	if cfg.vimhol == false then
		h.info("vimhol = false: auto-bootstrap disabled; multi-line sends and hc use the raw pty")
	else
		local vh = repl.vimhol_sml()
		if vh then
			h.ok("vimhol.sml: " .. vh)
		else
			h.warn("vimhol.sml not found under holdir", {
				"REPLs still work, but multi-line sends and hc degrade to the raw pty",
				"set config.holdir, or config.vimhol to an explicit path",
			})
		end
	end

	-- fifo transport --------------------------------------------------------
	h.start("hol4nvim: fifo transport")
	h.info("transport = " .. tostring(cfg.transport))
	local path = fifo.path()
	if not path then
		h.warn("no fifo path resolves", {
			"the fifo transport (to an external HOL session) is unavailable",
			"set config.fifo or config.holdir, or export $VIMHOL_FIFO",
		})
	else
		local st = vim.uv.fs_stat(path)
		if not st then
			h.info("fifo path: " .. path .. " (not created yet; made on demand)")
		elseif st.type ~= "fifo" then
			h.warn("fifo path exists but is not a fifo: " .. path, {
				"remove it, or point config.fifo elsewhere",
			})
		elseif fifo.ready(path) then
			h.ok("fifo: " .. path .. " (a reader is attached)")
		else
			h.info("fifo: " .. path .. " (exists; no reader attached right now)")
		end
	end

	-- tree-sitter syntax tier ----------------------------------------------
	h.start("hol4nvim: tree-sitter syntax tier")
	for _, lang in ipairs({ "holscript", "holterm", "sml" }) do
		local built = #vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", false) > 0
		if pcall(vim.treesitter.get_string_parser, "", lang) then
			h.ok(lang .. ": parser built and loadable")
		elseif built then
			h.warn("parser/" .. lang .. ".so is present but will not load", {
				"likely an ABI / Neovim-version mismatch; rebuild with `make parsers`",
			})
		else
			h.warn(lang .. ": parser not built", {
				'run `make parsers`, or add build = "make parsers" to the lazy spec',
				"(without it the regex highlighting tier is used instead)",
			})
		end
	end

	-- insert-mode completion -----------------------------------------------
	h.start("hol4nvim: completion")
	local completion = require("hol4nvim.completion")
	if completion.config.enabled == false then
		h.info("completion is toggled off (:HolCompletionToggle to enable)")
	else
		if pcall(require, "cmp") then
			h.ok("nvim-cmp present; the `hol4nvim` source is registered")
		else
			h.warn("nvim-cmp not found -- the completion source cannot attach", {
				"add nvim-cmp (hrsh7th/nvim-cmp) to the plugin's dependencies",
				"or set config.completion.enabled = false to silence this",
			})
		end
		if not completion.config.theorems then
			h.info("theorem completion off (config.completion.theorems = false); tactics only")
		elseif completion.cache.loaded then
			h.info(
				#completion.cache.theorems
					.. " theorem names cached (:HolCompletionRefresh to update)"
			)
		else
			h.info("theorem cache empty; it fills on a REPL start / hl / :HolCompletionRefresh")
		end
	end

	-- keymap prefix vs leader ----------------------------------------------
	h.start("hol4nvim: keymaps")
	if cfg.keymaps == false then
		h.info("keymaps = false: no buffer-local hol maps are installed")
	else
		local prefix = resolved_prefix(cfg.prefix)
		local collisions = M.prefix_collisions(prefix, keymaps.suffixes(), global_map_lhs())
		if #collisions == 0 then
			h.ok("prefix `" .. (cfg.prefix or "<localleader>") .. "` has no colliding longer maps")
		else
			local seen, lines = {}, {}
			for _, c in ipairs(collisions) do
				local line = vim.fn.keytrans(c.hol) .. " is delayed by " .. vim.fn.keytrans(c.culprit)
				if not seen[line] then
					seen[line] = true
					lines[#lines + 1] = line
				end
			end
			h.warn(
				"prefix collides with longer global maps -- each hol map below waits "
					.. "'timeoutlen' before firing:\n  "
					.. table.concat(lines, "\n  "),
				{
					"raise 'timeoutlen', or",
					'set config.prefix off your mapleader (e.g. "<localleader>"), or',
					"remove/shorten the colliding global maps",
				}
			)
		end
	end
end

return M
