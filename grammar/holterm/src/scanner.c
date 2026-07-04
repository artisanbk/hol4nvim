/*
 * External scanner for the holterm grammar (ROADMAP Phase 5c).
 *
 * Owns a single token: the nested (* ... *) comment (SML comments nest, which
 * a regex cannot express). Everything else in holterm is a plain lexer regex.
 * A lone '(' that is not followed by '*' is left for the internal lexer to
 * take as punctuation. No state survives between calls.
 */

#include "tree_sitter/parser.h"

#include <stdbool.h>

enum TokenType { COMMENT };

static void advance(TSLexer *lexer) { lexer->advance(lexer, false); }
static void skip(TSLexer *lexer) { lexer->advance(lexer, true); }

/* Positioned just after "(*". Consumes the (possibly nested) rest. */
static void scan_comment_body(TSLexer *lexer) {
	int depth = 1;
	while (depth > 0) {
		if (lexer->eof(lexer)) {
			return; /* unterminated: emit what we have; the tree stays usable */
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
}

bool tree_sitter_holterm_external_scanner_scan(
	void *payload, TSLexer *lexer, const bool *valid) {
	(void)payload;

	if (!valid[COMMENT]) {
		return false;
	}

	while (lexer->lookahead == ' ' || lexer->lookahead == '\t' ||
	       lexer->lookahead == '\r' || lexer->lookahead == '\n' ||
	       lexer->lookahead == '\f') {
		skip(lexer);
	}

	if (lexer->lookahead != '(') {
		return false;
	}
	advance(lexer);
	if (lexer->lookahead != '*') {
		return false; /* a lone '(': let the internal lexer take it */
	}
	advance(lexer);
	scan_comment_body(lexer);
	lexer->mark_end(lexer);
	lexer->result_symbol = COMMENT;
	return true;
}

void *tree_sitter_holterm_external_scanner_create(void) { return NULL; }
void tree_sitter_holterm_external_scanner_destroy(void *payload) {
	(void)payload;
}
unsigned tree_sitter_holterm_external_scanner_serialize(
	void *payload, char *buffer) {
	(void)payload;
	(void)buffer;
	return 0;
}
void tree_sitter_holterm_external_scanner_deserialize(
	void *payload, const char *buffer, unsigned length) {
	(void)payload;
	(void)buffer;
	(void)length;
}
