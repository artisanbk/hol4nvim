; Fold whole script blocks. The regex tier only folded Proof..QED;
; Definition/Datatype/(Co)Inductive..End now fold too.
; (Folding via tree-sitter is opt-in:
;   set foldmethod=expr foldexpr=v:lua.vim.treesitter.foldexpr())

(theorem) @fold
(definition) @fold
(datatype) @fold
(inductive) @fold
(theory_header) @fold
