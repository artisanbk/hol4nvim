--[[
  hol4nvim.transform -- reshape a selection into a proof-manager call.

  This is the "what to send" layer, orthogonal to repl's "how to send"
  (terminal vs fifo). Each function takes the raw selected text and returns the
  SML string to evaluate; repl's send() then routes it through a transport.

  Requires nothing from the rest of the plugin, so it never participates in a
  require cycle.
--]]

local M = {}

--[[
  strip_comments: remove SML `(* ... *)` comments from text before sending.
  Comments are semantically null but hazardous in transit: a multi-line
  comment can contain `Theorem`/`QED`-looking lines that confuse hol's
  line-oriented filter (and the incomplete-block guard). Character scanner
  because gsub can't do the two things that matter:
    - SML comments NEST:  (* a (* b *) c *)  is one comment
    - "(*" inside a string literal is not a comment

  Returns the stripped text, plus the line number of the outermost `(*`
  that never closes, or nil if all comments are balanced. An unclosed
  comment swallows everything after it (hol's own lexer nests identically),
  so callers should refuse to send and point at that line.
--]]
M.strip_comments = function(text)
	local out, i, n = {}, 1, #text
	local depth, in_string = 0, false
	local line, opens = 1, {}
	while i <= n do
		local c = text:sub(i, i)
		if c == "\n" then
			line = line + 1
		end
		if in_string then
			out[#out + 1] = c
			if c == "\\" then -- copy escaped char verbatim (handles \")
				local esc = text:sub(i + 1, i + 1)
				out[#out + 1] = esc
				if esc == "\n" then
					line = line + 1
				end
				i = i + 1
			elseif c == '"' then
				in_string = false
			end
			i = i + 1
		elseif depth > 0 then
			local two = text:sub(i, i + 1)
			if two == "(*" then
				depth = depth + 1
				opens[depth] = line
				i = i + 2
			elseif two == "*)" then
				depth = depth - 1
				i = i + 2
			else
				i = i + 1
			end
		elseif text:sub(i, i + 1) == "(*" then
			depth = 1
			opens[depth] = line
			i = i + 2
		else
			if c == '"' then
				in_string = true
			end
			out[#out + 1] = c
			i = i + 1
		end
	end
	return table.concat(out), depth > 0 and opens[1] or nil
end

--[[
  Tactic-token stripping (port of hol.vim's s:strip* + the HOLExpand /
  HOLPattern loops, hol.vim:141-159). A line grabbed out of a proof usually
  carries the combinator gluing it to its neighbours -- `>> tac`, `tac >>`,
  `THEN1 tac`, `tac THEN`, a trailing `(` or leading `)` -- which is noise
  when the tactic is applied on its own. Strip such tokens from both ends,
  repeatedly, so "apply this line to the goal" just works:
    leading:  , << >> >>~ ++ \\ >- >| >~  ) ] [   THEN THEN1 THENL by
    trailing: , << >> >>~ ++ \\ >- >| >~  ( [     THEN THEN1 THENL by
  Word tokens only count next to a delimiter (whitespace/parens/ends), so
  `standby` or `THENfoo` are never touched. Mid-text tokens are kept:
  `tac1 >> tac2` or `` `x` by tac `` pass through whole.
--]]
-- longest tokens first, so >>~ wins over >>, THENL/THEN1 over THEN
local lead_syms = { ">>~", "<<", ">>", "++", "\\\\", ">-", ">|", ">~", ",", ")", "]", "[" }
local trail_syms = { ">>~", "<<", ">>", "++", "\\\\", ">-", ">|", ">~", ",", "(", "[" }
local word_tokens = { "THENL", "THEN1", "THEN", "by" }

local function strip_tactic_tokens(text)
	local function boundary(c) -- delimiter, or nothing (text edge)
		return c == "" or c:match("[%s()]") ~= nil
	end

	local changed = true
	while changed do -- leading
		changed = false
		local t = text:gsub("^%s+", "")
		for _, tok in ipairs(lead_syms) do
			if t:sub(1, #tok) == tok then
				local nxt = t:sub(#tok + 1, #tok + 1)
				-- upstream: symbol must be followed by a word start or delim
				if boundary(nxt) or nxt:match("[%w_]") then
					t = t:sub(#tok + 1)
					break
				end
			end
		end
		for _, tok in ipairs(word_tokens) do
			if t:sub(1, #tok) == tok and boundary(t:sub(#tok + 1, #tok + 1)) then
				t = t:sub(#tok + 1)
				break
			end
		end
		if t ~= text then
			text = t
			changed = true
		end
	end

	changed = true
	while changed do -- trailing
		changed = false
		local t = text:gsub("%s+$", "")
		for _, tok in ipairs(trail_syms) do
			if #t >= #tok and t:sub(-#tok) == tok then
				t = t:sub(1, #t - #tok)
				break
			end
		end
		for _, tok in ipairs(word_tokens) do
			if #t > #tok and t:sub(-#tok) == tok then
				-- upstream: a trailing word token must follow a delimiter
				if boundary(t:sub(-#tok - 1, -#tok - 1)) then
					t = t:sub(1, #t - #tok)
					break
				end
			end
		end
		if t ~= text then
			text = t
			changed = true
		end
	end
	return text
end

--[[
  expand: apply the selection as a tactic to the current goal. Strips the
  leading/trailing combinator tokens (see above), then wraps as
  proofManagerLib.expand, eta-expanded over the goal exactly as upstream
  HOLExpand does (hol.vim:137-138):
      proofManagerLib.expand(fn HOLgoal => ( <selection> ) HOLgoal)
--]]
M.expand = function(text)
	return "proofManagerLib.expand(fn HOLgoal => ("
		.. strip_tactic_tokens(text)
		.. ") HOLgoal)"
end

-- Upstream's s:delim: the token boundary characters around tactic keywords.
local delim = "[%s()]"

--[[
  goal: set the selection as the current goal (port of HOLGoal,
  hol.vim:100-107). The selection must include the quotation marks:
      `!a b. a + b = b + a`  ->  proofManagerLib.g(`!a b. a + b = b + a`)
  Trailing commas/whitespace are stripped (upstream's `,\_s*)\%$` loop), so a
  goal yanked out of a list context still parses.
--]]
M.goal = function(text)
	return "proofManagerLib.g(" .. text:gsub("[%s,]*$", "") .. ")"
end

--[[
  subgoal: prove the selection as a subgoal via bossLib.sg (port of
  HOLSubgoal, hol.vim:161-168). A trailing " by <tactic>" is stripped, so the
  whole  `term` by tac  line can be selected as-is.
--]]
M.subgoal = function(text)
	local at = text:find(delim .. "by" .. delim)
	if at then
		text = text:sub(1, at - 1)
	end
	return "proofManagerLib.expand(bossLib.sg(" .. text .. "))"
end

--[[
  suffices: "it suffices to show the selection" via bossLib.qsuff_tac (port
  of HOLSuffices, hol.vim:170-177). Strips a trailing " suffices_by <tactic>"
  the same way subgoal strips " by".
--]]
M.suffices = function(text)
	local at = text:find(delim .. "suffices_by" .. delim)
	if at then
		text = text:sub(1, at - 1)
	end
	return "proofManagerLib.expand(bossLib.qsuff_tac(" .. text .. "))"
end

--[[
  pattern: apply the selection as a tactic to the sub-goals selected by a
  pattern via Q.SELECT_GOAL_LT (port of HOLPattern, hol.vim:228-238).
  Like upstream, shares the combinator-token stripping with expand.
--]]
M.pattern = function(text)
	return "proofManagerLib.expand_list(Q.SELECT_GOAL_LT("
		.. strip_tactic_tokens(text)
		.. "))"
end

--[[
  quiet: send the selection wrapped in HOL_Interactive.toggle_quietdec()
  toggles (port of HOLSendQuiet, hol.vim:94-98), so declaration results are
  not printed -- e.g. an `open` that would dump hundreds of bindings.
  The final toggle's ";" comes from the sender.
--]]
local toggle_quiet = "val _ = HOL_Interactive.toggle_quietdec();"

M.quiet = function(text)
	return toggle_quiet
		.. "\n"
		.. text
		.. ";\n"
		.. "val _ = HOL_Interactive.toggle_quietdec()"
end

--[[
  uqgoal: set an UNQUOTED goal -- the selection is bare term text with no
  backquotes, e.g. the statement lines of a Theorem block (port of
  HOLUQGoal, hol.vim:109-139). Three cases, in priority order:

  1. A `Resume <thm>[<label>]:` header anywhere in the selection sets up the
     suspended sub-goal via markerLib.set_suspended_goal.
  2. A line starting with `Proof` splits the selection: what precedes is the
     goal, and the Proof line (plus any lines after it, joined) becomes the
     BasicProvers.mk_tacmod string, so `Proof[attrs]` attributes apply.
  3. Otherwise the whole selection is the goal, with the default "Proof".

  The goal is wrapped in ``double backquotes``, exactly as upstream.
--]]
M.uqgoal = function(text)
	local lines = vim.split(text, "\n", { plain = true })

	for _, line in ipairs(lines) do
		local thm, label = line:match("^Resume%s+(%S-)%[([^%]]+)%]%s*:")
		if thm then
			return 'markerLib.set_suspended_goal {suspension_name = "'
				.. thm
				.. '", label_name = "'
				.. label
				.. '"}'
		end
	end

	local proof_at
	for i = #lines, 1, -1 do
		if lines[i]:find("^Proof") then
			proof_at = i
			break
		end
	end

	local goal, tacmod
	if proof_at then
		goal = table.concat(lines, "\n", 1, proof_at - 1)
		-- upstream joins the Proof line with everything after it (VGJ):
		-- single spaces, continuation lines' leading whitespace dropped
		local tail = {}
		for i = proof_at, #lines do
			tail[#tail + 1] = (lines[i]:gsub("^%s+", ""))
		end
		tacmod = table.concat(tail, " ")
	else
		goal = text
		tacmod = "Proof"
	end

	return "proofManagerLib.new_goalstack([],``"
		.. goal
		.. '``) (BasicProvers.mk_tacmod "'
		.. tacmod
		.. '") I'
end

return M
