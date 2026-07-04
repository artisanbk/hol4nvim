/**
 * holterm --- tree-sitter grammar for the HOL4 TERM language (ROADMAP Phase
 * 5c). Injected by the holscript grammar into quotation interiors and into
 * the unquoted term bodies of Definition/Datatype/Inductive blocks.
 *
 * Deliberately a LENIENT token stream, not a real expression parser. HOL's
 * concrete term syntax is user-extensible (the parser grows new infixes,
 * binders and mixfix rules as theories load), so no fixed grammar can parse
 * arbitrary terms -- and highlighting does not need to. `source_file` is a
 * flat `repeat(choice(token...))`, so any input tokenises without ERROR
 * nodes; every token maps to a standard highlight capture. This already beats
 * the regex tier (which recognises only a hand-curated symbol vocabulary and
 * mismatches quote delimiters).
 *
 * The one external token is the nested `(* *)` comment (regex cannot nest);
 * everything else is a plain lexer regex.
 */

module.exports = grammar({
	name: "holterm",

	externals: ($) => [$.comment],
	extras: ($) => [/\s/, $.comment],
	word: ($) => $.identifier,

	rules: {
		source_file: ($) => repeat($._token),

		_token: ($) =>
			choice(
				$.binder,
				$.keyword,
				$.boolean,
				$.antiquotation,
				$.number,
				$.string,
				$.char,
				$.type_var,
				$.operator,
				$.identifier,
				$.punctuation,
			),

		// Term binders. `\` (lambda) is kept out of the operator character
		// class, and `/\` `\/` are spelled out as operators below, so a lone
		// `\` binds while `\/` (longer match) tokenises as one operator -- no
		// lexical precedence needed (which would otherwise beat longest-match).
		binder: () =>
			choice(
				"!",
				"?!",
				"?",
				"@",
				"\\",
				"λ", // λ
				"∀", // ∀
				"∃!", // ∃!
				"∃", // ∃
			),

		// Whole-word term keywords (kept honest by `word:` keyword extraction,
		// so `then` in `thenceforth` is not a keyword).
		keyword: () =>
			choice(
				"if",
				"then",
				"else",
				"let",
				"in",
				"and",
				"case",
				"of",
				"do",
				"od",
				"with",
			),

		// HOL's boolean constants.
		boolean: () => choice("T", "F"),

		// ML antiquotation splice: ^ident (bare `^` is an operator, so `^(e)`
		// still reads as operator + parenthesised term). 5c-stretch injects SML.
		antiquotation: () => token(/\^[A-Za-z_][A-Za-z0-9_']*/),

		number: () =>
			token(
				choice(
					/0[xX][0-9a-fA-F]+/,
					/0[bB][01]+/,
					/[0-9]+\.[0-9]+/,
					/[0-9]+/,
				),
			),

		string: () => token(seq('"', repeat(choice(/[^"\\]/, /\\[\s\S]/)), '"')),
		char: () => token(seq('#"', repeat(choice(/[^"\\]/, /\\[\s\S]/)), '"')),

		// Type variables: 'a, 'b, and common unicode forms.
		type_var: () => token(choice(/'[A-Za-z_][A-Za-z0-9_']*/, /[α-δ]/)),

		// Any maximal run of symbolic operator characters is one operator token
		// -- no need to enumerate HOL's (extensible) operator set. Binder and
		// antiquotation characters (! ? @ \ ^-splice) are excluded so they keep
		// their own meaning; `/\` and `\/` are spelled out (their `\` is not in
		// the class) so conjunction/disjunction munch whole while a lone `\`
		// still binds.
		operator: () =>
			choice(
				"/\\", // conjunction /\
				"\\/", // disjunction \/
				/[-#%&*+/:<>=|~$^.]+/,
				// unicode logical / arithmetic / set operators (binders λ∀∃ and
				// arrows excluded so they tokenise on their own)
				/[←→↦↔⇒⇔∧∨¬≠≤≥∈∉⊆⊂∪∩×∘·≡⊢⊕⊗]+/,
			),

		identifier: () => /[A-Za-z_][A-Za-z0-9_']*/,

		punctuation: () => choice("(", ")", "[", "]", "{", "}", ",", ";"),
	},
});
