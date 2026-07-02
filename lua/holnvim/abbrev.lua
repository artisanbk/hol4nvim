--[[
  holnvim.abbrev -- ASCII -> Unicode insert-mode abbreviations for HOL
  terms, a port of upstream holabs.vim. Opt-in like upstream (there you
  source holabs.vim yourself): enable with `abbreviations = true` in
  setup(). unabbrev() is the reverse (port of HOLUnab), exposed as
  :HolUnabbrev.
--]]

local M = {}

-- { ascii, unicode } in holabs.vim order
M.pairs = {
	{ "/\\", "∧" },
	{ "\\/", "∨" },
	{ "~", "¬" },
	{ "==>", "⇒" },
	{ "<=", "≤" },
	{ ">=", "≥" },
	{ "<=>", "⇔" },
	{ "<>", "≠" },
	{ "!", "∀" },
	{ "?", "∃" },
	{ "\\", "λ" },
	{ "IN", "∈" },
	{ "NOTIN", "∉" },
	{ "INTER", "∩" },
	{ "UNION", "∪" },
	{ "SUBSET", "⊆" },
	{ "PSUBSET", "⊂" },
	{ "RING", "∘" },
	{ "PROVES", "⊢" },
	{ "DPLUS", "⧺" },
}

--- Install the buffer-local abbreviations (called from the ftplugin; no-op
--- unless config.abbreviations is set).
M.attach = function()
	if not require("holnvim.repl").config.abbreviations then
		return
	end
	-- upstream: iskeyword+=>,/,\ so /\ ==> <= etc. abbreviate as whole words
	vim.opt_local.iskeyword:append({ ">", "/", "\\" })
	for _, pair in ipairs(M.pairs) do
		vim.keymap.set("ia", pair[1], pair[2], { buffer = true })
	end
end

--- Replace the Unicode forms back with ASCII over a line range (port of
--- HOLUnab; upstream is a per-line :s -- here the default range is the
--- whole buffer, which is what you want before committing a file).
M.unabbrev = function(line1, line2)
	local lines = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
	for i, line in ipairs(lines) do
		for _, pair in ipairs(M.pairs) do
			-- unicode chars are not Lua-pattern magic; ascii sides may be,
			-- so replace via plain find
			local out, pos = {}, 1
			while true do
				local s, e = line:find(pair[2], pos, true)
				if not s then
					out[#out + 1] = line:sub(pos)
					break
				end
				out[#out + 1] = line:sub(pos, s - 1)
				out[#out + 1] = pair[1]
				pos = e + 1
			end
			line = table.concat(out)
		end
		lines[i] = line
	end
	vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, lines)
end

return M
