/**
 * holscript --- skeleton tree-sitter grammar for HOL4 Script.sml files
 * (ROADMAP Phase 5b).
 *
 * Scope: script-level structure only. Block interiors (`term`, `tactics`)
 * and everything between blocks (`ml_chunk`) are opaque spans that Phase 5c
 * fills in via injections. The external scanner (src/scanner.c) owns every
 * context-sensitive token: nested comments, quotation delimiters that must
 * match in style, block keywords recognised only at line start, the opaque
 * chunk spans, and the name lists of Theory-header sections.
 *
 * Matched quotations come in three node types by delimiter WIDTH
 * (quotation_single `..`, quotation_double ``..``, quotation_unicode ‘..’/“..”)
 * so injections.scm can trim delimiters with a fixed per-node #offset! and
 * inject holterm into the interior; a wrong-style closer is quotation_mismatched.
 */

// The quotation alternatives, shared by every context that admits a quotation.
const quotations = ($) => [
	$.quotation_single,
	$.quotation_double,
	$.quotation_unicode,
	$.quotation_mismatched,
];

module.exports = grammar({
	name: "holscript",

	// Order must match enum TokenType in src/scanner.c.
	externals: ($) => [
		$.comment,
		$.ml_chunk,
		$._term_chunk,
		$._tactic_chunk,
		$._kw_theorem,
		$._kw_triviality,
		$._kw_definition,
		$._kw_datatype,
		$._kw_inductive,
		$._kw_coinductive,
		$._kw_type,
		$._kw_overload,
		$._kw_proof,
		$._kw_termination,
		$._kw_qed,
		$._kw_end,
		$._kw_theory,
		$._kw_ancestors,
		$._kw_libs,
		$.section_names,
		$.quotation_single,
		$.quotation_double,
		$.quotation_unicode,
		$.quotation_mismatched,
		// external so it outranks the chunk tokens right after Proof/names
		$.attributes,
	],

	extras: ($) => [/\s/, $.comment],

	rules: {
		source_file: ($) =>
			repeat(
				choice(
					$.theory_header,
					$.theorem,
					$.definition,
					$.datatype,
					$.inductive,
					$.type_abbrev,
					...quotations($),
					$.string,
					$.hol_string,
					$.ml_chunk,
				),
			),

		// New-style script header: Theory name + Ancestors/Libs name lists.
		theory_header: ($) =>
			seq(
				alias($._kw_theory, "Theory"),
				field("name", $.identifier),
				optional($.attributes),
				repeat($.header_section),
			),

		header_section: ($) =>
			seq(
				choice(
					alias($._kw_ancestors, "Ancestors"),
					alias($._kw_libs, "Libs"),
				),
				optional($.section_names),
			),

		// Theorem foo[attrs]: term Proof[attrs] tactics QED
		// Theorem foo[attrs] = <ML>   (the ML continues as a plain ml_chunk)
		theorem: ($) =>
			seq(
				choice(
					alias($._kw_theorem, "Theorem"),
					alias($._kw_triviality, "Triviality"),
				),
				field("name", $.identifier),
				optional($.attributes),
				choice(
					seq(
						":",
						optional($.term),
						alias($._kw_proof, "Proof"),
						optional($.attributes),
						optional($.tactics),
						alias($._kw_qed, "QED"),
					),
					"=",
				),
			),

		definition: ($) =>
			seq(
				alias($._kw_definition, "Definition"),
				field("name", $.identifier),
				optional($.attributes),
				":",
				optional($.term),
				optional(
					seq(alias($._kw_termination, "Termination"), optional($.tactics)),
				),
				alias($._kw_end, "End"),
			),

		datatype: ($) =>
			seq(
				alias($._kw_datatype, "Datatype"),
				":",
				optional($.term),
				alias($._kw_end, "End"),
			),

		inductive: ($) =>
			seq(
				choice(
					alias($._kw_inductive, "Inductive"),
					alias($._kw_coinductive, "CoInductive"),
				),
				field("name", $.identifier),
				":",
				optional($.term),
				alias($._kw_end, "End"),
			),

		type_abbrev: ($) =>
			seq(
				choice(alias($._kw_type, "Type"), alias($._kw_overload, "Overload")),
				field("name", $.identifier),
				optional($.attributes),
				"=",
				choice(...quotations($), $.string),
			),

		// Opaque block interiors; 5c injects holterm / sml into these.
		term: ($) =>
			repeat1(
				choice(
					alias($._term_chunk, $.term_chunk),
					...quotations($),
					$.string,
					$.hol_string,
				),
			),

		tactics: ($) =>
			repeat1(
				choice(
					alias($._tactic_chunk, $.tactic_chunk),
					...quotations($),
					$.string,
					$.hol_string,
				),
			),

		identifier: () => /[A-Za-z][A-Za-z0-9_']*/,
		string: () => token(seq('"', repeat(choice(/[^"\\]/, /\\[\s\S]/)), '"')),
		hol_string: () => token(seq("«", /[^»]*/, "»")),
	},
});
