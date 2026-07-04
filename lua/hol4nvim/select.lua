--[[
  hol4nvim.select -- selection-movement helpers, a port of HOLSelect and its
  mappings (hol.vim:213-271). No REPL involved: these just make the visual
  selection that the send maps then consume.
--]]

local M = {}

--[[
  Select from the previous match of `lpat` to the next match of `rpat`
  (charwise). Mirrors upstream: search back (allowing a match at the
  cursor), start visual, search forward; if the right end is missing, drop
  the selection and restore the cursor.
--]]
local function hol_select(lpat, rpat)
	local save = vim.fn.getpos(".")
	if vim.fn.search(lpat, "Wbc") == 0 then
		return false
	end
	vim.cmd("normal! v")
	if vim.fn.search(rpat, "W") == 0 then
		vim.cmd("normal! \27")
		vim.fn.setpos(".", save)
		return false
	end
	vim.fn.search(rpat, "ce")
	vim.cmd("normal! zv")
	return true
end

--- ht : select the enclosing `term` (ASCII or ‘smart’ quotes).
M.term = function()
	hol_select("`\\|‘", "`\\|’")
end

--- hT : select the enclosing ``term`` (or “smart” quotes).
M.quoted_term = function()
	hol_select("``\\|“", "``\\|”")
end

--[[
  ha : select the enclosing Theorem/Triviality block's statement + Proof
  lines -- exactly the selection hG wants. Upstream selects Theorem..Proof,
  then `Vo+` makes it linewise and shifts the start down one line, dropping
  the Theorem line itself.
--]]
M.theorem = function()
	if
		hol_select(
			"^Triviality\\|^Theorem",
			"^Proof$\\|^Proof\\[\\_.\\{-}\\]"
		)
	then
		vim.cmd("normal! Vo+")
	end
end

return M
