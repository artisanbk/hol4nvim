--[[
  End-to-end: the :HolExternalSetup loader. Point $HOL_CONFIG at the ACTUAL
  file the plugin generates (repl.write_hol_config) and boot a real hol. This
  proves the generated SML parses and attaches Vimhol -- so a hol you start
  yourself in your own terminal becomes drivable out of the box, which is the
  whole point of the feature. (tests/e2e_preload.lua covers a hand-written
  preloading config; this covers OUR generated one, whose only failure mode is
  silent: a broken loader is dropped with "[Ignoring configuration ...]".)
      nvim --headless -u init.lua -l tests/e2e_external.lua
--]]

local t = dofile("tests/util.lua")

local repl = require("hol4nvim.repl")

vim.o.swapfile = false
-- edit a hol4script buffer so repl.open's cwd/altname resolve as in real use
vim.cmd.edit("examples/TestScript.sml")

local notifications = {}
vim.notify = function(msg, level)
	notifications[#notifications + 1] = msg
	print(("[notify %s] %s"):format(tostring(level), msg))
end

if repl.which_hol() == "" then
	t.fatal("hol not found: e2e needs HOL4 (set $HOLDIR). Run `make test-unit` for the HOL-free tier.")
end

-- Generate the real loader and point hol at it (NOCONFIG off so it runs).
local loader, reason = repl.write_hol_config()
if not loader then
	t.fatal("write_hol_config failed: " .. tostring(reason))
end
t.check("loader written to the data dir", vim.fn.filereadable(loader) == 1)

vim.env.HOL_NOCONFIG = nil
vim.env.HOL_CONFIG = loader

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

local function wait_for(name, pat, ms, want)
	want = want or 1
	local ok = vim.wait(ms or 30000, function()
		return occurrences(term_text():gsub("\n", ""), pat) >= want
	end, 200)
	if not ok then
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

-- The sentinel is printed by the 7a pty bootstrap regardless; the point here is
-- that hol did NOT reject the generated loader on the way (a syntax error would
-- surface as an "[Ignoring configuration ...]" line and no Vimhol tail).
wait_for("REPL ready with the generated loader", "hol4nvim: vimhol ready", 90000)
t.check(
	"hol accepted the generated loader (no HOL_CONFIG parse error)",
	occurrences(term_text():gsub("\n", ""), "Ignoring configuration from HOL_CONFIG") == 0
)
vim.wait(2000) -- let the loader's Vimhol fifo tail settle

-- Vimhol attached via the loader; the 7a bootstrap's guarded `use` then no-ops
-- (Vimhol already bound), so exactly ONE tail owns the session pipe and a
-- pipe-routed multi-line send evaluates exactly once.
repl.send("val hnv_external_probe =\n  40 + 2;")
wait_for("pipe-routed send evaluates", "val hnv_external_probe = 42")
vim.wait(2000) -- give any (buggy) second tail time to double-deliver
t.check(
	"generated loader did not double-attach (exactly one eval)",
	occurrences(term_text():gsub("\n", ""), "val hnv_external_probe = 42") == 1
)

repl.close()
local closed = vim.wait(15000, function()
	return repl.current() == nil
end, 200)
t.check("session closes and prunes the stack", closed)

vim.env.HOL_CONFIG = nil
t.finish()
