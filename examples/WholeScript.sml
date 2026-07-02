(* ========================================================================= *)
(* holnvim h! (send whole document) demo -- a LINEAR script file.            *)
(*                                                                           *)
(* Unlike TestScript.sml (a keymap demo made of bare fragments), every       *)
(* statement here is complete, so the whole file batch-evaluates. Workflow:  *)
(*                                                                           *)
(*   1. hx               open a REPL                                         *)
(*   2. hl on the open   load the dependencies                               *)
(*   3. h!               send the whole file: open lines are dropped,        *)
(*                       comments stripped, everything else evaluated        *)
(*                                                                           *)
(* Expect: val four = 4, and thm bindings for whole_add, whole_sub,          *)
(* double_def and dbl_even. (Selecting everything with ggVG and hs works    *)
(* too -- multi-line sends travel as a script file via the Vimhol pipe.)     *)
(*                                                                           *)
(* A real script would end with `val _ = export_theory ();` -- omitted here  *)
(* so the demo leaves no WholeTheory.* files behind.                         *)
(* ========================================================================= *)
open HolKernel boolLib bossLib arithmeticTheory;

val _ = new_theory "Whole";

(* Comments are fine anywhere, (* even nested *), and a comment mentioning   *)
(* Theorem foo: with no QED must confuse neither hol nor holnvim's guard.    *)

fun double x = x + x;

val four = double 2;

Theorem whole_add:
  !a b. a + b = b + a
Proof
  decide_tac
QED

(* A multi-step proof, with a comment between the tactics. *)
Theorem whole_sub:
  !n. 1 <= n ==> n - 1 + 1 = n
Proof
  rpt strip_tac (* strip the quantifier and the antecedent *)
  >> decide_tac
QED

Definition double_def:
  dbl n = n + n
End

Theorem dbl_even:
  !n. EVEN (dbl n)
Proof
  (* rw normalises n + n to 2 * n, which EVEN_DOUBLE closes *)
  rw[double_def, arithmeticTheory.EVEN_DOUBLE]
QED
