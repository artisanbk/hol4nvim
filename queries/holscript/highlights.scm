; holscript highlights (Phase 5b). Standard captures only, so every
; colorscheme's defaults apply. Block interiors (term_chunk/tactic_chunk/
; ml_chunk) are deliberately uncaptured until 5c injects real grammars.

(comment) @comment

(string) @string
(hol_string) @string

; quotations: the whole span reads as a special string, and injections.scm
; hands the interior (delimiters trimmed) to the holterm grammar on top
(quotation_single) @string.special
(quotation_double) @string.special
(quotation_unicode) @string.special

; mismatched delimiter styles (`x + y’) -- the regex tier rendered these
; as well-formed quotations
(quotation_mismatched) @error

[
  "Theorem"
  "Triviality"
  "Definition"
  "Datatype"
  "Inductive"
  "CoInductive"
  "Type"
  "Overload"
  "Proof"
  "Termination"
  "QED"
  "End"
] @keyword

; The new-style theory header. Deliberately NOT plain @keyword: the names
; these introduce are @module, and a colorscheme that renders @keyword and
; @module alike leaves "Ancestors" indistinguishable from the theories it
; imports. @keyword.import / @keyword.directive are the standard captures for
; exactly this (import statements, module declarations), so they separate in
; any scheme that distinguishes them at all -- and stay overridable by name.
"Theory" @keyword.directive

[
  "Ancestors"
  "Libs"
] @keyword.import

":" @punctuation.delimiter
"=" @operator

(theorem name: (identifier) @function)
(definition name: (identifier) @function)
(inductive name: (identifier) @function)
(type_abbrev name: (identifier) @type)
(theory_header name: (identifier) @module)

(attributes) @attribute
(section_names) @module
