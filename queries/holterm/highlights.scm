; holterm highlights (Phase 5c). Standard captures only, so every colorscheme
; applies. holterm is a lenient token stream injected into HOL term text
; (quotation interiors and Definition/Datatype/Inductive bodies).

(comment) @comment

(binder) @keyword.operator
(keyword) @keyword
(boolean) @boolean

(number) @number
(string) @string
(char) @character
(type_var) @type

(antiquotation) @variable

(operator) @operator

(identifier) @variable

((punctuation) @punctuation.bracket
 (#any-of? @punctuation.bracket "(" ")" "[" "]" "{" "}"))
((punctuation) @punctuation.delimiter
 (#any-of? @punctuation.delimiter "," ";"))
