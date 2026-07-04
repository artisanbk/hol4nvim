# Vendored: tree-sitter-sml

Source: https://github.com/MatthewFluet/tree-sitter-sml
Commit: `558bf67cb18b85b5a2c8355401166dd715413c3c`
        ("Initial update to tree-sitter-cli 0.25.4")
License: MIT (see `LICENSE`).

## What is vendored

- `grammar.js` — grammar source (kept for regeneration only; not built by users).
- `src/parser.c`, `src/scanner.c`, `src/tree_sitter/*.h` — the generated parser
  and its hand-written scanner. `make parsers` compiles these into
  `parser/sml.so` with nothing but `cc`, exactly like the `holscript` grammar.

The matching `queries/sml/highlights.scm` (also MIT, same commit) lives with the
other query sets so Neovim core loads it off the plugin rtp.

## Why this commit and not HEAD

Upstream HEAD (`fd4b495`) adopts tree-sitter's `reserved` word construct, which
requires parser ABI 15 (tree-sitter CLI 0.25+). hol4nvim pins ABI 14 so the
parsers load on Neovim 0.10's bundled runtime; `558bf67` is the last commit
before the `reserved` experiment and regenerates cleanly at
`tree-sitter generate --abi 14`.

## Regenerating (maintainer only)

`make grammar` runs `tree-sitter generate --abi 14` in every `grammar/*/` dir,
including this one. Users never need the CLI — the generated C is committed.

## Role in the plugin

`sml.so` is the injection target for `holscript`'s `ml_chunk` nodes (the plain
ML between script blocks) — see `queries/holscript/injections.scm`. It is
optional: if `parser/sml.so` is absent the injection simply does not fire and
the chunk stays an opaque span.
