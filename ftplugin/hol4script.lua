--[[
  Per-buffer setup for HOL4 script files. Runs on every hol4script buffer.
  Keymaps live in lua/holnvim/keymaps.lua; buffer-local options belong here.
--]]

--[[
  Reload guard: if current buffer has already been set up, then exit.
  Avoids reapplying keymaps / options
--]]
if vim.b.did_ftplugin then
	return
end

vim.b.did_ftplugin = true

require("holnvim.keymaps").attach()
require("holnvim.abbrev").attach() -- no-op unless config.abbreviations

--[[
  Highlighting (ROADMAP Phase 5): prefer the tree-sitter holscript parser
  when it has been built (5b, `make parsers`); vim.treesitter.start disables
  regex syntax for the buffer itself. Until then the pcall fails silently
  and the regex port (syntax/hol4script.vim, 5a) loads as usual.
--]]
pcall(vim.treesitter.language.register, "holscript", "hol4script")
pcall(vim.treesitter.start, 0, "holscript")
