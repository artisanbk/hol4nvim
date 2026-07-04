--[[
  End-to-end, the OTHER bootstrap branch (Phase 6a / 7d): a hol whose config
  ALREADY loads Vimhol. The 7a guarded `use` must then no-op -- NOT attach a
  second fifo tail to the session pipe -- while the sentinel still prints and a
  pipe-routed multi-line send evaluates EXACTLY ONCE. (tests/e2e.lua covers the
  config-less branch, a hol booted with HOL_NOCONFIG=1.)

  This is the smoke script the 7d note deferred to Phase 6; it costs a second
  hol boot, which is acceptable at release time.
      nvim --headless -u init.lua -l tests/e2e_preload.lua
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

local vimhol = repl.vimhol_sml()
if not vimhol then
	t.fatal("vimhol.sml not resolvable; cannot simulate a preloading hol-config")
end

-- A user hol-config that loads Vimhol itself (upstream's template is exactly
-- this one line). check-intconfig.sml runs it before hol reads stdin, so the
-- 7a guard observes Vimhol already bound.
local config = vim.fn.tempname() .. ".sml"
vim.fn.writefile({ 'use "' .. vimhol .. '";' }, config)

-- Point hol at our config and make sure NOCONFIG is off, so the config runs
-- (and ~/.hol-config.sml does not -- HOL_CONFIG replaces the default search).
vim.env.HOL_NOCONFIG = nil
vim.env.HOL_CONFIG = config

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

-- The sentinel prints even though the guard no-ops (Vimhol already bound by
-- the config): the 7a bootstrap always announces readiness.
wait_for("REPL ready with a preloading config", "hol4nvim: vimhol ready", 90000)
vim.wait(2000) -- let the config's Vimhol fifo tail settle

-- A pipe-routed multi-line send evaluates EXACTLY ONCE. The config's Vimhol
-- tails the session pipe (repl.open exports VIMHOL_FIFO to it); if the guard
-- had wrongly re-used vimhol.sml, a second tail on the same pipe would steal
-- or duplicate deliveries -- either way this count would not be 1.
repl.send("val preload_probe =\n  40 + 2;")
wait_for("pipe-routed send evaluates", "val preload_probe = 42")
vim.wait(2000) -- give any (buggy) second tail time to double-deliver
t.check(
	"guarded bootstrap did not double-attach (exactly one eval)",
	occurrences(term_text():gsub("\n", ""), "val preload_probe = 42") == 1
)

repl.close()
local closed = vim.wait(15000, function()
	return repl.current() == nil
end, 200)
t.check("session closes and prunes the stack", closed)

vim.env.HOL_CONFIG = nil
t.finish()
