(* ========================================================================= *)
(* holnvim feature test script                                               *)
(*                                                                           *)
(* Launch from the repo root:                                                *)
(*     nvim -u init.lua examples/TestScript.sml                              *)
(*                                                                           *)
(* Maps are written hx, hs ... below, with localleader h as in the upstream  *)
(* vimhol docs. Substitute your own <localleader> for the leading h (the     *)
(* demo init.lua currently sets it to SPACE, so hx means <space>x). With     *)
(* localleader h, plain h still moves left: hh is mapped through.            *)
(*                                                                           *)
(* Implemented:   hx open REPL   hX close REPL   hs send (hw alias)         *)
(*                h! send whole document -- demo in examples/WholeScript.sml *)
(*                he expand tactic   hg set goal   hG unquoted goal         *)
(*                hS subgoal   hF suffices   hP pattern   hl load deps      *)
(*                hu quiet send   hb backup   hB restore   hv save          *)
(*                hd drop   hp print   hr restart   hR rotate               *)
(*                hc interrupt  (counts: 3hb, 2hR)                          *)
(*                ht hT ha selections   hy hn display toggles               *)
(*                insert abbreviations + :HolUnabbrev                       *)
(* Not yet (see ROADMAP.md): syntax highlighting                            *)
(* ========================================================================= *)

(* ------------------------------------------------------------------------- *)
(* 1. hl  (load deps): cursor on the next line, press hl. Loads each         *)
(*    dependency, then executes the line itself inside quietdec toggles (so  *)
(*    the open's binding dump is suppressed), and finally prints             *)
(*    "HOLLoad ... completed". If nothing appears, check :messages.          *)
(* ------------------------------------------------------------------------- *)
open HolKernel boolLib bossLib arithmeticTheory;

val _ = new_theory "Test";

(* ------------------------------------------------------------------------- *)
(* 2. hs  (send line): first open the REPL with hx, then cursor on the next  *)
(*    line and press hs. Expect: val two = 2: int                            *)
(* ------------------------------------------------------------------------- *)
val two = 1 + 1;

(* Visual send: select all three lines below with V, then hs.                *)
fun triple x =
  let val y = x + x
  in y + x end;

(* Then check it: hs on the next line. Expect: val it = 9: int               *)
val it_should_be_nine = triple 3;

(* hu (quiet send): like hs, but wrapped in HOL_Interactive.toggle_quietdec  *)
(* toggles, so the result binding is NOT printed -- handy for `open` lines,  *)
(* which would dump hundreds of bindings. hu the first line below (expect    *)
(* silence), then hs the second to confirm it really evaluated.              *)
val quietly = 99;
val quietly_check = quietly + 1;

(* ------------------------------------------------------------------------- *)
(* 3. Interactive goal workflow.                                             *)
(*    hg (set goal): cursor on the quotation line below, press hg. The      *)
(*    selection/line must include the backquotes. Expect "Initial goal:".   *)
(* ------------------------------------------------------------------------- *)
`!a b. a + b = b + a`

(*    Equivalent by hand, sent with hs (a bare expression, not              *)
(*    `val _ = ...` -- binding to _ would suppress the goal printout):      *)
proofManagerLib.g `!a b. a + b = b + a`;

(* 3a. he (expand tactic): cursor on the next line, press he.                *)
(*     Expect the goal to be proved ("Initial goal proved").                 *)
decide_tac

(* 3b. Or prove it in smaller steps: undo with hs on the restart line, then  *)
(*     he each tactic line in order.                                         *)
proofManagerLib.restart ();

Induct_on `a`
>> decide_tac

(* Visual-mode he: select the next two lines with V, then he.                *)
asm_rewrite_tac [ADD_CLAUSES]
>> decide_tac

(* 3c. Drop the goal when done playing:                                      *)
proofManagerLib.drop ();

(* 3d. Combinator-token stripping: lines lifted from a proof script keep     *)
(*     their >> / THEN / \\ glue. he strips such tokens from BOTH ends and   *)
(*     applies the bare tactic (mid-line combinators are kept, so a whole    *)
(*     `tac1 >> tac2` still works). Set the goal with hg, then he the two    *)
(*     noisy lines below in order -- trailing >> first, leading >> second:   *)
`!n. n <= n + n`

rpt strip_tac >>
>> decide_tac

(*     Word-glue works too: hr restarts the proved goal, then he the next    *)
(*     line -- the trailing THEN is stripped and decide_tac proves it.       *)
decide_tac THEN

(*     Clean up with hd, or:                                                 *)
proofManagerLib.drop ();

(* ------------------------------------------------------------------------- *)
(* 4. he error handling: expanding a non-tactic should print a HOL error in  *)
(*    the REPL, not crash nvim. Cursor on the next line, press he.           *)
(* ------------------------------------------------------------------------- *)
val this_is_not_a_tactic = 0

(* ------------------------------------------------------------------------- *)
(* 5. A complete theorem block. Select the whole block linewise (V from the  *)
(*    Theorem line through QED) and hs it -- expect a thm binding. A         *)
(*    selection that misses the QED is refused with a warning: sent raw, it  *)
(*    would wedge the REPL's filter at its '#' prompt (Ctrl-C recovers).     *)
(*                                                                           *)
(*    hG (unquoted goal): select the statement + Proof lines (no             *)
(*    backquotes, no Theorem line) and press hG -- the statement becomes     *)
(*    the goal, honouring any Proof[attributes]. Prove interactively with    *)
(*    he, drop with the 3c line. Later: ha should make that selection.      *)
(* ------------------------------------------------------------------------- *)
Theorem add_comm_test:
  !a b. a + b = b + a
Proof
  decide_tac
QED

(* hS (subgoal): set the sub_add_test goal (hg on the next line), he on the *)
(* rpt strip_tac line, then visually select `0 < n` by decide_tac (from the  *)
(* backquote to end of line, NOT the leading >>) and press hS -- the         *)
(* trailing "by decide_tac" is stripped and `0 < n` becomes a subgoal.       *)
(*                                                                           *)
(* he also strips combinator noise: pressing he directly on the whole        *)
(* `>> `0 < n` by decide_tac` line (or on `rpt strip_tac >>`-style lines)    *)
(* drops the leading/trailing >> THEN \\ etc. and applies the tactic.        *)
`!n. 1 <= n ==> n - 1 + 1 = n`

Theorem sub_add_test:
  !n. 1 <= n ==> n - 1 + 1 = n
Proof
  rpt strip_tac
  >> `0 < n` by decide_tac
  >> decide_tac
QED

(* hF (suffices): with a goal set, visually select the text between the      *)
(* comment markers on the next line and press hF -- it sends                 *)
(* qsuff_tac `n <> 0` after stripping the trailing "suffices_by ...".        *)
(* `n <> 0` suffices_by decide_tac *)

(* 5b. hG hands-on: select the TWO lines below with V (a bare statement, no  *)
(*     backquotes, plus its Proof line) and press hG. The statement becomes  *)
(*     the goal via new_goalstack; Proof[attributes] would be honoured.      *)
(*     Prove it with he on the decide_tac of 3a, then hd to drop.            *)
!a b c. a + (b + c) = (a + b) + c
Proof

(* 5c. Selection helpers: ht selects the enclosing `term`, hT the ``term``,  *)
(*     and ha the statement + Proof lines of the Theorem block at/above the  *)
(*     cursor -- exactly hG's selection. Try: cursor on add_comm_test's      *)
(*     decide_tac, ha, then hG; or ht on the quotation line of section 3.    *)

(* ------------------------------------------------------------------------- *)
(* 6. Proof-manager controls: a guided tour on a two-subgoal proof.          *)
(*    (i)   hg the quotation line below, then he conj_tac -> 2 subgoals.     *)
(*    (ii)  hp reprints the proof state at any time.                         *)
(*    (iii) hR rotates to the other subgoal (2hR rotates twice = back).      *)
(*    (iv)  hv saves the state; he on the simp[] line proves one subgoal;    *)
(*          hb backs that step up again; hB returns to the hv save point.    *)
(*    (v)   Counts repeat hb hB hd: e.g. 3hb backs up three steps.           *)
(*    (vi)  hd drops the whole attempt when you are done.                    *)
(* ------------------------------------------------------------------------- *)
`T /\ (1 + 1 = 2)`

conj_tac

simp[]

(* ------------------------------------------------------------------------- *)
(* 7. hc (interrupt): hg the goal below, then select BOTH tactic lines with  *)
(*    V and he -- rpt ONCE_REWRITE_TAC[ADD_SYM] swaps a+b forever. Being a   *)
(*    multi-line send it travels via the Vimhol pipe, so hc can interrupt    *)
(*    it (expect "Vim interrupt" then an Interrupt exception). hd to clean   *)
(*    up. NOTE: single-line sends go through the terminal's stdin, out of    *)
(*    hc's reach -- for those, press Ctrl-C inside the REPL window itself.   *)
(* ------------------------------------------------------------------------- *)
`!a b. a + b + b = b + a + b`

rpt (ONCE_REWRITE_TAC
       [arithmeticTheory.ADD_SYM])

(* ------------------------------------------------------------------------- *)
(* 8. Unicode: goals and terms may mix ASCII and unicode notation freely.    *)
(*    Send with hs after the REPL is up:                                     *)
(* ------------------------------------------------------------------------- *)
proofManagerLib.g `∀a b. a + b = b + a`;
proofManagerLib.drop ();

(* 8b. Display toggles + abbreviations.                                       *)
(*     hy toggles Globals.show_types: hs the next line before and after --   *)
(*     with types shown, expect “(1 :num) + (2 :num)”.                       *)
``1 + 2``

(*     hn toggles unicode printing: hs the next line before and after --     *)
(*     with unicode avoided, ¬T prints as ~T.                                *)
``¬T``

(*     Insert abbreviations (needs setup({ abbreviations = true }), as the   *)
(*     demo init.lua does): in insert mode type  /\  IN  ==>  ! ...          *)
(*     followed by a space to get  ∧ ∈ ⇒ ∀.  :HolUnabbrev converts unicode  *)
(*     back to ASCII (whole buffer, or a visual range) -- try it on the      *)
(*     next line, then undo with u:                                          *)
val abbrev_demo = `∀x. x ∈ s ⇒ x ≤ y`;

(* ------------------------------------------------------------------------- *)
(* 9. Comment handling: select this whole section -- comments included --    *)
(*    and hs it. Comments (even nested (* like this *)) are stripped before  *)
(*    sending; a selection that is ONLY comments is not sent at all, and an  *)
(*    UNCLOSED comment is refused with its line number.                      *)
(* ------------------------------------------------------------------------- *)
val comments_ok = (* inline (* nested *) noise *) 42;

(* ------------------------------------------------------------------------- *)
(* 10. h! (send whole document) does NOT work on THIS file, by design: it is *)
(*     a keymap demo full of bare fragments (tactic lines like Induct_on /   *)
(*     >> decide_tac, bare quotations) that cannot be batch-parsed -- the    *)
(*     same is true of selecting everything and pressing hs. For a working   *)
(*     h! demonstration on a real, linear script, open:                      *)
(*         examples/WholeScript.sml                                          *)
(* ------------------------------------------------------------------------- *)

(* ------------------------------------------------------------------------- *)
(* 11. hX: close the REPL. The hol process exits (Ctrl-D); the terminal      *)
(*     buffer window stays open, same as upstream vimhol.                    *)
(* ------------------------------------------------------------------------- *)

val _ = export_theory ();
