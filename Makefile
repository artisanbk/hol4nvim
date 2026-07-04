NVIM ?= nvim
CC ?= cc

# Every grammar under grammar/<name>/ builds to parser/<name>.so. Vendored
# grammars carry a PROVENANCE.md and are excluded from regeneration/corpus
# runs (we ship their generated C as-is; upstream owns their grammar.js).
GRAMMARS := $(notdir $(wildcard grammar/*))
PARSERS := $(addprefix parser/,$(addsuffix .so,$(GRAMMARS)))

.PHONY: test test-ci test-unit test-ts test-e2e parsers grammar test-grammar clean

# Full suite. test-e2e needs a working HOL4 (hol on PATH or $$HOLDIR set);
# test-unit runs anywhere; test-ts builds the tree-sitter parsers (needs cc).
test: test-unit test-ts test-e2e

# What CI runs: the HOL-free tiers (no HOL4 install needed). Mirrors the
# GitHub Actions workflow so `make test-ci` reproduces it locally.
test-ci: test-unit test-ts

test-unit:
	$(NVIM) --headless -u init.lua -l tests/unit.lua

test-ts: parsers
	$(NVIM) --headless -u init.lua -l tests/treesitter.lua

test-e2e:
	$(NVIM) --headless -u init.lua -l tests/e2e.lua examples/TestScript.sml
	$(NVIM) --headless -u init.lua -l tests/e2e_preload.lua

# Compile the vendored parser C for every grammar (what a user's lazy `build`
# hook runs; the only requirement is a C compiler). A grammar's scanner.c is
# compiled in when present.
parsers: $(PARSERS)

parser/%.so: grammar/%/src/parser.c
	@mkdir -p parser
	$(CC) -shared -fPIC -O2 -Igrammar/$*/src \
		grammar/$*/src/parser.c \
		$$(test -f grammar/$*/src/scanner.c && echo grammar/$*/src/scanner.c) \
		-o $@

# Maintainer-only: regenerate src/parser.c from grammar.js and run the corpus
# tests (needs the tree-sitter CLI). ABI 14 keeps Neovim 0.10 happy. Vendored
# grammars (with a PROVENANCE.md) are skipped -- their C ships as vendored.
grammar:
	@for d in grammar/*/; do \
		if [ -f "$$d/PROVENANCE.md" ]; then echo "skip vendored $$d"; continue; fi; \
		echo "generate $$d"; ( cd "$$d" && tree-sitter generate --abi 14 ); \
	done

test-grammar:
	@for d in grammar/*/; do \
		if [ -f "$$d/PROVENANCE.md" ]; then continue; fi; \
		if [ -d "$$d/test" ]; then echo "test $$d"; ( cd "$$d" && tree-sitter test ); fi; \
	done

clean:
	rm -rf parser
