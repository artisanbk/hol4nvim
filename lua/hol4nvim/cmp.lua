--[[
  hol4nvim.cmp -- the nvim-cmp source object. Deliberately thin: the vocabulary
  and the theorem cache live in hol4nvim.completion; this only adapts them to
  cmp's source protocol and gates on the enabled flag + the hol4script filetype.
  Registered by completion.register().
--]]

local completion = require("hol4nvim.completion")

local source = {}

source.new = function()
	return setmetatable({}, { __index = source })
end

--- Only offer completions in HOL script buffers, and only while enabled
--- (:HolCompletionToggle flips completion.config.enabled).
function source:is_available()
	return vim.bo.filetype == "hol4script" and completion.is_enabled()
end

function source:get_debug_name()
	return "hol4nvim"
end

--- HOL identifiers are word characters plus the prime that ends names like
--- `STRICT'` / `o'`; keep cmp's keyword boundary in step so a leading prime or
--- an embedded one does not split the token.
function source:get_keyword_pattern()
	return [[\%(\k\|'\)\+]]
end

function source:complete(_, callback)
	-- Populate the theorem cache lazily the first time completion is asked for
	-- once a session exists; this request returns tactics only, the next one
	-- (isIncomplete makes cmp re-query) sees the theorems.
	if completion.config.theorems and not completion.cache.loaded then
		completion.schedule_refresh()
	end
	callback({ items = completion.items(), isIncomplete = not completion.cache.loaded })
end

return source
