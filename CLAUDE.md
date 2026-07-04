# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

hol4nvim: a standalone lazy.nvim plugin porting the Vim configuration shipped with [HOL4](https://hol-theorem-prover.org/) (the HOL4 interactive theorem prover) to Neovim. The plugin is working; see ROADMAP.md for the authoritative parity status, architecture notes, and remaining phases.

## Structure

- `lua/hol4nvim/` — the plugin. Layering (keep it): `transform.lua` is pure string→string reshapers with no plugin dependencies; `repl.lua` owns transport/session state and `M.config`; `fifo.lua` is the fifo transport (never requires `repl` at load time); `init.lua` is `setup(opts)` + user commands; `keymaps.lua` is the single keymap registry; `health.lua` is `:checkhealth hol4nvim` (re-runs the resolvers, never duplicates their logic); `search.lua` is the theorem-database search (`hf`/`hm`), which captures results over the one-way transport via a temp file since `send()` has no return channel; `completion.lua` owns the completion vocabulary (static tactics + a DB-snapshot theorem cache, refreshed off the `HolReplStarted`/`HolLoaded` User autocmds `repl` fires) and `cmp.lua` is the thin nvim-cmp source over it.
- `ftplugin/hol4script.lua`, `ftdetect/hol4script.lua`, `syntax/hol4script.vim` — buffer-local attach, `*Script.sml` detection, regex highlighting.
- `grammar/*/` + `queries/*/` — the tree-sitter syntax tier (5b/5c); `doc/hol4nvim.txt` + `doc/tags` — the `:help` doc.
- `init.lua` (repo root) — NOT the plugin: an isolated demo/dev entry point (`nvim -u init.lua examples/TestScript.sml`).
- `tests/` — `make test` = `tests/unit.lua` (HOL-free) + `tests/treesitter.lua` (needs `make parsers`) + `tests/e2e.lua` and `tests/e2e_preload.lua` (drive a real hol REPL; slow). `make test-unit` for the fast tier. Extend both when adding features.

## Conventions

- Lua with the `vim.*` API, not Vimscript (exception: `syntax/hol4script.vim`, a verbatim upstream port).
- Filetype-specific behavior goes in `ftplugin/`; global setup in the module's `setup()`.
- Deliberate divergences from upstream (guarded sends, comment stripping, unified transport, ...) are documented in ROADMAP.md — don't "fix" them back to upstream behavior.
- `README.MD` is the source of truth for user-facing docs; `doc/hol4nvim.txt` is its vimdoc rendering. Change both together and regenerate `doc/tags` (`:helptags doc`) so `:help` doesn't drift.

## Reference

The behavior being ported is HOL4's `tools/editor-modes/vim/` configuration (`hol.vim`, `holabs.vim`, `hol4script.vim`, `filetype.vim`, `vimhol.sml`); a local checkout lives at `/home/lazarys/Gitscripts/HOL/tools/editor-modes/vim/`. Consult it when deciding what the port should reproduce.
