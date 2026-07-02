--[[
  Tiny shared harness for the headless test scripts (see Makefile).
  Collects pass/fail per check, prints a summary, and exits non-zero on
  any failure so `make test` fails properly.
--]]

local M = { failed = 0, passed = 0 }

-- io.write, not print: in `nvim -l`, print starts a new line instead of
-- ending one, which garbles interleaved/final output.
local function line(s)
	io.write(s .. "\n")
end

M.check = function(name, cond, detail)
	if cond then
		M.passed = M.passed + 1
		line("ok   " .. name)
	else
		M.failed = M.failed + 1
		line("FAIL " .. name .. (detail and ("  (" .. detail .. ")") or ""))
	end
	return cond
end

M.finish = function()
	line(("--- %d passed, %d failed ---"):format(M.passed, M.failed))
	os.exit(M.failed == 0 and 0 or 1)
end

M.fatal = function(msg)
	line("FATAL " .. msg)
	os.exit(1)
end

return M
