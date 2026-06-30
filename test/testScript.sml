open HolKernel boolLib bossLib;

val _ = new_theory "Test";

(* Send this line with \s once the REPL is up (\x). *)
val one_plus_one = 1 + 1;

(* Goal: put cursor in the quotes, set it with \g, then prove interactively. *)
Theorem add_comm_example:
  !a b. a + b = b + a
Proof
 (* With the goal set, send this tactic line with \e to expand it. )
  rw[]
QED

val _ = export_theory ();
