; holscript injections (Phase 5c). Each opaque span from the skeleton grammar
; hands its interior to a real grammar, so terms and ML get proper highlighting
; instead of one flat colour. Every injection is best-effort: if the target
; parser is not built (parser/<lang>.so absent) the span simply stays opaque.
;
;   ml_chunk       -> sml       (plain ML between script blocks)
;   tactic_chunk   -> sml       (tactics are SML; quotations within are
;                                separate nodes, injected as holterm below)
;   term_chunk     -> holterm   (unquoted term text in Definition/Datatype/
;                                Inductive bodies)
;   quotation ...  -> holterm   (the `...` term language; delimiters trimmed
;                                per style via #offset! -- see below)

((ml_chunk) @injection.content
 (#set! injection.language "sml"))

((tactic_chunk) @injection.content
 (#set! injection.language "sml"))

((term_chunk) @injection.content
 (#set! injection.language "holterm"))

; Quotation interiors -> holterm. Each quotation node type has a fixed
; delimiter width, so #offset! trims the opening/closing delimiter (in bytes)
; and only the term text is handed on. quotation_mismatched is left alone
; (its @error highlight stands; injecting into a broken quote adds nothing).
((quotation_single) @injection.content
 (#offset! @injection.content 0 1 0 -1)
 (#set! injection.language "holterm"))

((quotation_double) @injection.content
 (#offset! @injection.content 0 2 0 -2)
 (#set! injection.language "holterm"))

((quotation_unicode) @injection.content
 (#offset! @injection.content 0 3 0 -3)
 (#set! injection.language "holterm"))
