/*
 * External scanner for the holscript grammar (ROADMAP Phase 5b).
 *
 * Owns every context-sensitive token:
 *   - nested (* ... *) comments;
 *   - quotations: delimiter styles must MATCH (` pairs with `, ‘ with ’,
 *     `` with ``, “ with ”) -- a wrong-style closer yields
 *     quotation_mismatched, which highlights query as an error where the
 *     regex tier silently rendered it well-formed. Matched quotations split
 *     by delimiter WIDTH -- QUOT_SINGLE (1-byte `..`), QUOT_DOUBLE (2-byte
 *     ``..``), QUOT_UNICODE (3-byte ‘..’ / “..”) -- so an injection query can
 *     trim the delimiters with a fixed per-node #offset! and hand the
 *     interior to holterm;
 *   - block keywords, recognised only at line start (after optional
 *     whitespace) -- fixing the regex tier's column-0-only limitation
 *     while `val Theorem = ...` mid-line still reads as plain ML;
 *   - the opaque chunk spans (ml_chunk / term / tactics interiors), which
 *     stop before any quotation/string/comment opener and before any
 *     line-start block keyword;
 *   - section_names: the name list of a Theory-header Ancestors/Libs
 *     section (rest of the keyword line plus indented continuation lines).
 *
 * No state survives between calls, so serialize/deserialize are empty.
 */

#include "tree_sitter/parser.h"

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

enum TokenType {
	COMMENT,
	ML_CHUNK,
	TERM_CHUNK,
	TACTIC_CHUNK,
	KW_THEOREM,
	KW_TRIVIALITY,
	KW_DEFINITION,
	KW_DATATYPE,
	KW_INDUCTIVE,
	KW_COINDUCTIVE,
	KW_TYPE,
	KW_OVERLOAD,
	KW_PROOF,
	KW_TERMINATION,
	KW_QED,
	KW_END,
	KW_THEORY,
	KW_ANCESTORS,
	KW_LIBS,
	SECTION_NAMES,
	QUOT_SINGLE,    /* `...`   (single backtick, 1-byte delimiters) */
	QUOT_DOUBLE,    /* ``...`` (double backtick, 2-byte delimiters) */
	QUOT_UNICODE,   /* ‘...’ or “...” (3-byte delimiters) */
	QUOT_MISMATCHED,
	ATTRIBUTES,
};

/* Unicode quotation delimiters. */
#define LSQUO 0x2018 /* ‘ */
#define RSQUO 0x2019 /* ’ */
#define LDQUO 0x201C /* “ */
#define RDQUO 0x201D /* ” */
#define LAQUO 0x00AB /* « */
#define RAQUO 0x00BB /* » */

static const struct {
	const char *word;
	enum TokenType token;
} KEYWORDS[] = {
	{ "Theorem", KW_THEOREM },       { "Triviality", KW_TRIVIALITY },
	{ "Definition", KW_DEFINITION }, { "Datatype", KW_DATATYPE },
	{ "Inductive", KW_INDUCTIVE },   { "CoInductive", KW_COINDUCTIVE },
	{ "Type", KW_TYPE },             { "Overload", KW_OVERLOAD },
	{ "Proof", KW_PROOF },           { "Termination", KW_TERMINATION },
	{ "QED", KW_QED },               { "End", KW_END },
	{ "Theory", KW_THEORY },         { "Ancestors", KW_ANCESTORS },
	{ "Libs", KW_LIBS },
};
#define N_KEYWORDS (sizeof(KEYWORDS) / sizeof(KEYWORDS[0]))
#define MAX_WORD 16 /* longest keyword + 1 */

static bool is_inline_space(int32_t c) {
	return c == ' ' || c == '\t' || c == '\r' || c == '\f' || c == 0x0B;
}

static bool is_space(int32_t c) {
	return is_inline_space(c) || c == '\n';
}

static bool is_word(int32_t c) {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
	       (c >= '0' && c <= '9') || c == '_' || c == '\'';
}

/* Chunk spans stop before any of these (a token of its own starts). */
static bool is_special(int32_t c) {
	return c == '`' || c == '"' || c == LSQUO || c == RSQUO || c == LDQUO ||
	       c == RDQUO || c == LAQUO || c == RAQUO;
}

static void advance(TSLexer *lexer) { lexer->advance(lexer, false); }
static void skip(TSLexer *lexer) { lexer->advance(lexer, true); }

/*
 * Read a word into buf (NUL-terminated, truncated at MAX_WORD-1 but fully
 * consumed). Returns its length in characters consumed.
 */
static int read_word(TSLexer *lexer, char *buf) {
	int n = 0;
	while (is_word(lexer->lookahead)) {
		if (n < MAX_WORD - 1) {
			buf[n] = (char)(lexer->lookahead < 128 ? lexer->lookahead : '?');
		}
		n++;
		advance(lexer);
	}
	buf[n < MAX_WORD - 1 ? n : MAX_WORD - 1] = '\0';
	return n;
}

/* -1 when buf is no keyword. */
static int keyword_token(const char *buf) {
	for (unsigned i = 0; i < N_KEYWORDS; i++) {
		if (strcmp(buf, KEYWORDS[i].word) == 0) {
			return (int)KEYWORDS[i].token;
		}
	}
	return -1;
}

/* Positioned just after "(*". Consumes the (possibly nested) rest. */
static bool scan_comment_body(TSLexer *lexer) {
	int depth = 1;
	while (depth > 0) {
		if (lexer->eof(lexer)) {
			return true; /* unterminated: emit what we have; the tree stays usable */
		}
		if (lexer->lookahead == '(') {
			advance(lexer);
			if (lexer->lookahead == '*') {
				depth++;
				advance(lexer);
			}
		} else if (lexer->lookahead == '*') {
			advance(lexer);
			if (lexer->lookahead == ')') {
				depth--;
				advance(lexer);
			}
		} else {
			advance(lexer);
		}
	}
	return true;
}

/*
 * Positioned at a quotation opener. Consumes the whole quotation and
 * reports which token it is.
 */
static enum TokenType scan_quotation(TSLexer *lexer) {
	int32_t open = lexer->lookahead;
	bool dbl = false;
	advance(lexer);
	if (open == '`' && lexer->lookahead == '`') {
		dbl = true;
		advance(lexer);
	} else if (open == LDQUO) {
		dbl = true;
	}

	for (;;) {
		if (lexer->eof(lexer)) {
			return QUOT_MISMATCHED; /* unterminated */
		}
		int32_t c = lexer->lookahead;
		if (!dbl) {
			if (c == '`') {
				advance(lexer);
				return open == '`' ? QUOT_SINGLE : QUOT_MISMATCHED;
			}
			if (c == RSQUO) {
				advance(lexer);
				return open == LSQUO ? QUOT_UNICODE : QUOT_MISMATCHED;
			}
		} else {
			if (c == '`') {
				advance(lexer);
				if (lexer->lookahead == '`') {
					advance(lexer);
					return open == '`' ? QUOT_DOUBLE : QUOT_MISMATCHED;
				}
				continue; /* lone backtick inside `` ... ``: content */
			}
			if (c == RDQUO) {
				advance(lexer);
				return open == LDQUO ? QUOT_UNICODE : QUOT_MISMATCHED;
			}
		}
		advance(lexer);
	}
}

/*
 * The Ancestors/Libs name list: bare names on the rest of the keyword
 * line and on indented continuation lines. A word at column 0 (the next
 * section keyword, or code) ends the list, as does any non-name symbol.
 */
static bool scan_section_names(TSLexer *lexer, bool crossed_newline) {
	bool have = false;
	for (;;) {
		if (lexer->eof(lexer)) {
			break;
		}
		int32_t c = lexer->lookahead;
		if (is_space(c)) {
			if (c == '\n') {
				crossed_newline = true;
			}
			advance(lexer);
			continue;
		}
		if (!is_word(c) || (c >= '0' && c <= '9')) {
			break; /* names start with a letter; symbols end the section */
		}
		if (crossed_newline && lexer->get_column(lexer) == 0) {
			break; /* column 0: next keyword / next declaration */
		}
		while (is_word(lexer->lookahead)) {
			advance(lexer);
		}
		lexer->mark_end(lexer);
		have = true;
	}
	return have;
}

/*
 * Opaque span: consume until a special delimiter, a comment opener, or a
 * line-start block keyword. Only emitted nonempty.
 */
static bool scan_chunk(TSLexer *lexer, bool at_line_start) {
	bool have = false;
	char buf[MAX_WORD];
	for (;;) {
		if (lexer->eof(lexer)) {
			break;
		}
		int32_t c = lexer->lookahead;
		if (is_special(c)) {
			break;
		}
		if (c == '(') {
			advance(lexer); /* not yet part of the token: mark_end pending */
			if (lexer->lookahead == '*') {
				break; /* comment opener; token ends at the last mark_end */
			}
			lexer->mark_end(lexer);
			have = true;
			at_line_start = false;
			continue;
		}
		if (c == '\n') {
			advance(lexer);
			at_line_start = true;
			continue; /* newline joins the token only if content follows */
		}
		if (is_inline_space(c)) {
			advance(lexer);
			if (have) {
				/* interior space extends the span; leading space does not */
				continue;
			}
			continue;
		}
		if (at_line_start && is_word(c) && !(c >= '0' && c <= '9')) {
			read_word(lexer, buf);
			if (keyword_token(buf) >= 0) {
				break; /* line-start keyword; token ends at last mark_end */
			}
			lexer->mark_end(lexer);
			have = true;
			at_line_start = false;
			continue;
		}
		advance(lexer);
		lexer->mark_end(lexer);
		have = true;
		at_line_start = false;
	}
	return have;
}

bool tree_sitter_holscript_external_scanner_scan(
	void *payload, TSLexer *lexer, const bool *valid) {
	(void)payload;

	bool at_line_start = lexer->get_column(lexer) == 0;
	while (is_space(lexer->lookahead)) {
		if (lexer->lookahead == '\n') {
			at_line_start = true;
		}
		skip(lexer);
	}
	if (lexer->eof(lexer)) {
		return false;
	}

	int32_t c = lexer->lookahead;

	/* Comments: highest priority; also probed so chunks can absorb '('. */
	if (c == '(' && valid[COMMENT]) {
		advance(lexer);
		if (lexer->lookahead == '*') {
			advance(lexer);
			scan_comment_body(lexer);
			lexer->mark_end(lexer);
			lexer->result_symbol = COMMENT;
			return true;
		}
		/* plain '(': fall through into chunk scanning if a chunk may
		   start here (the consumed char becomes chunk content) */
		if (valid[ML_CHUNK] || valid[TERM_CHUNK] || valid[TACTIC_CHUNK]) {
			lexer->mark_end(lexer);
			bool more = scan_chunk(lexer, false);
			(void)more; /* '(' alone is already content */
			lexer->result_symbol = valid[TERM_CHUNK]   ? TERM_CHUNK
			                       : valid[TACTIC_CHUNK] ? TACTIC_CHUNK
			                                             : ML_CHUNK;
			return true;
		}
		return false;
	}

	/* Line-start block keywords. */
	if (at_line_start && is_word(c) && !(c >= '0' && c <= '9')) {
		uint32_t col = lexer->get_column(lexer);
		char buf[MAX_WORD];
		read_word(lexer, buf);
		int kw = keyword_token(buf);
		if (kw >= 0 && valid[kw]) {
			lexer->mark_end(lexer);
			lexer->result_symbol = (enum TokenType)kw;
			return true;
		}
		/* an INDENTED non-keyword word continues a header name list;
		   a column-0 one belongs to the next construct instead */
		if (valid[SECTION_NAMES] && col > 0) {
			lexer->mark_end(lexer);
			scan_section_names(lexer, true);
			lexer->result_symbol = SECTION_NAMES;
			return true;
		}
		/* not a (valid) keyword: the word can open a chunk */
		if (valid[ML_CHUNK] || valid[TERM_CHUNK] || valid[TACTIC_CHUNK]) {
			lexer->mark_end(lexer);
			scan_chunk(lexer, false);
			lexer->result_symbol = valid[TERM_CHUNK]   ? TERM_CHUNK
			                       : valid[TACTIC_CHUNK] ? TACTIC_CHUNK
			                                             : ML_CHUNK;
			return true;
		}
		return false;
	}

	/* [attrs] right after a name or Proof -- external so it beats the
	   chunk tokens, which would otherwise absorb the bracket. */
	if (c == '[' && valid[ATTRIBUTES]) {
		advance(lexer);
		while (!lexer->eof(lexer) && lexer->lookahead != ']' &&
		       lexer->lookahead != '\n') {
			advance(lexer);
		}
		if (lexer->lookahead == ']') {
			advance(lexer);
			lexer->mark_end(lexer);
			lexer->result_symbol = ATTRIBUTES;
			return true;
		}
		return false;
	}

	/* Quotations. */
	if ((c == '`' || c == LSQUO || c == LDQUO) &&
	    (valid[QUOT_SINGLE] || valid[QUOT_DOUBLE] || valid[QUOT_UNICODE] ||
	     valid[QUOT_MISMATCHED])) {
		enum TokenType t = scan_quotation(lexer);
		lexer->mark_end(lexer);
		lexer->result_symbol = t;
		return true;
	}

	/* Theory-header section name lists. */
	if (valid[SECTION_NAMES]) {
		/* only name-shaped starts; anything else ends the section */
		if (is_word(c) && !(c >= '0' && c <= '9')) {
			bool crossed = at_line_start;
			if (crossed && lexer->get_column(lexer) == 0) {
				return false; /* column 0 belongs to the next construct */
			}
			if (scan_section_names(lexer, crossed)) {
				lexer->result_symbol = SECTION_NAMES;
				return true;
			}
		}
		return false;
	}

	/* Opaque chunks. */
	if (valid[ML_CHUNK] || valid[TERM_CHUNK] || valid[TACTIC_CHUNK]) {
		if (is_special(c)) {
			return false; /* a quotation/string token starts here instead */
		}
		if (scan_chunk(lexer, at_line_start)) {
			lexer->result_symbol = valid[TERM_CHUNK]   ? TERM_CHUNK
			                       : valid[TACTIC_CHUNK] ? TACTIC_CHUNK
			                                             : ML_CHUNK;
			return true;
		}
	}

	return false;
}

void *tree_sitter_holscript_external_scanner_create(void) { return NULL; }
void tree_sitter_holscript_external_scanner_destroy(void *payload) {
	(void)payload;
}
unsigned tree_sitter_holscript_external_scanner_serialize(
	void *payload, char *buffer) {
	(void)payload;
	(void)buffer;
	return 0;
}
void tree_sitter_holscript_external_scanner_deserialize(
	void *payload, const char *buffer, unsigned length) {
	(void)payload;
	(void)buffer;
	(void)length;
}
