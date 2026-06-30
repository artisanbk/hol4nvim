--[[
  holnvim.transform -- reshape a selection into a proof-manager call.

  This is the "what to send" layer, orthogonal to repl's "how to send"
  (terminal vs fifo). Each function takes the raw selected text and returns the
  SML string to evaluate; repl's send() then routes it through a transport.

  Requires nothing from the rest of the plugin, so it never participates in a
  require cycle.
--]]

local M = {}

--[[
  expand: apply the selection as a tactic to the current goal. Wraps it as
  proofManagerLib.expand, eta-expanded over the goal exactly as upstream
  HOLExpand does (hol.vim:137-138):
      proofManagerLib.expand(fn HOLgoal => ( <selection> ) HOLgoal)

  Scope A: no token-stripping yet -- select clean tactic text. Upstream's he
  additionally strips leading/trailing tactic tokens (THEN, >>, by, brackets,
  ...) so a sloppy selection still parses; that is a later refinement.
--]]
M.expand = function(text)
	return "proofManagerLib.expand(fn HOLgoal => (" .. text .. ") HOLgoal)"
end

return M
