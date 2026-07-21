# Changelog

All notable changes to hol4nvim are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims
to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### External-session auto-setup
- `:HolExternalSetup` makes a `hol` you start yourself in a terminal (not the
  in-vim `hx` REPL) attach to the Vimhol fifo out of the box. It writes a
  machine-agnostic loader to `stdpath("data")/hol4nvim/hol-config.sml` and
  appends a managed `export HOL_CONFIG=… VIMHOL_FIFO=…` block to your shell rc
  (fish gets `set -gx`). **No `~/.hol-config.sml` is created** — the loader
  lives in Neovim's data dir.
- The rc is derived from `$SHELL` (`~/.zshrc`, `~/.bashrc`, `config.fish`);
  the new `shell_rc` option or a `:HolExternalSetup <path>` argument overrides
  it. The block is written only on the explicit command, between markers, so
  re-running updates it in place and deleting the block undoes it — the plugin
  never edits a shell rc on `setup()`.
- The loader resolves `$HOME` and `vimhol.sml` (from `$HOLDIR`) at hol-runtime,
  so it is not tied to the machine that wrote it, and is regenerated on every
  `setup()`. Because `$HOL_CONFIG` replaces HOL's own config search, it runs
  your own hol-config first, then attaches Vimhol — guarded so a preloading
  config is never re-tailed.
- The "no fifo reader" recipe now resolves a real `vimhol.sml` path instead of
  a `<HOLDIR>` placeholder when only the fifo path is known, and points at
  `:HolExternalSetup` for the permanent one-time setup.
- `:checkhealth hol4nvim` reports the loader file and whether `$HOL_CONFIG`
  points at it.
- New `auto_shell_rc` option (default `false`): `setup()` maintains the managed
  block itself, so external sessions need no command at all. Off by default —
  the rc is still only written on an explicit request, which this flag is.

### Syntax
- The new-style theory header no longer colours its keywords like the names
  they introduce. `Theory` is `@keyword.directive` and `Ancestors`/`Libs` are
  `@keyword.import` (they were plain `@keyword`, indistinguishable from the
  `@module` names under them in colorschemes that render the two alike). The
  regex tier, which did not recognise the header at all and left the keywords
  unhighlighted, now has `HOLHeaderKey` (→ `Include`) and `HOLHeaderName`
  (→ `Identifier`). See `hol4nvim-theory-header` for overriding them.

### Fixed
- `holdir()` and `vimhol_sml()` expand `~` themselves instead of relying on
  `setup()` to have done it. Callers that drive `repl.config` directly
  (`:checkhealth`, tests, other plugins) got a literal `~/…` that failed every
  `filereadable()` check, then an error telling them to set `config.holdir` —
  which was set, and correct.
- `vimhol_sml()` returns why it failed, so "you disabled the bootstrap"
  (`vimhol = false`) no longer reports as "vimhol.sml not resolved (set
  config.holdir or config.vimhol)", which pointed at a missing HOL install
  instead of the switch the user had deliberately flipped. The not-found
  message now also names the directory that was searched.
- `:checkhealth hol4nvim` reports `vimhol = false` as a warning naming what it
  costs (external sessions included, not just `hx`), and reports whether the
  managed block is actually present in the rc — the check that distinguishes
  "never set up" from "set up, but this shell predates it".

## [0.1.0] — 2026-07-04

First release. Full parity with HOL4's upstream `tools/editor-modes/vim/`
configuration, ported to Neovim as a standalone lazy.nvim plugin, plus
out-of-the-box setup (no dotfiles or exported environment variables).

Maps are shown with `<localleader>` set to `h` (HOL's convention), e.g. `hx`.

### REPL & transport
- `hx` / `hX` start and close a HOL4 REPL in a split; session stack pruned on
  exit.
- HOL discovery chain: `config.hol_cmd` → `.HOLMK/lastmaker` → `config.holdir`
  → `$HOLDIR/bin/hol` → `hol` on `$PATH`. A directory `hol_cmd` (the `bin/`
  dir or the HOL root) is accepted, and `~` is expanded in path options.
- Unified `transport = "auto"` send layer: delivers to the in-vim `:terminal`
  REPL, or to an external HOL session over the Vimhol fifo. Multi-line sends
  auto-route through the session's own Vimhol pipe for real script-file
  parsing; single lines go straight to the pty.
- REPLs started by `hx` auto-load `vimhol.sml` via a guarded `use` (no
  `~/.hol-config.sml` needed); it no-ops if your config already loads Vimhol,
  and prints a `hol4nvim: vimhol ready` sentinel.
- The "no fifo reader" warning names the fifo and the exact recipe to start an
  external session, and creates the fifo so the recipe works.

### Sending & proof workflow
- Send raw SML (`hs`, `hw` alias), quietly (`hu`), or the whole document
  (`h!` / `:HolSendDocument`, dropping `open`/`Theory`/`Ancestors`/`Libs`).
- Proof transforms: expand (`he`), goal (`hg`), unquoted goal (`hG`), subgoal
  (`hS`), suffices (`hF`), pattern goal (`hP`), with upstream combinator-token
  stripping.
- Dependency loading (`hl`) via holdeptool, including new-style `Theory`
  headers.
- Proof-manager controls: `hb hB hv hd hp hr hR hc` (counts repeat where
  upstream does); `hc` interrupt reaches the running tactic over the Vimhol
  pipe, else Ctrl-C.
- Selection helpers `ht hT ha`; display toggles `hy hn`; `hh` passthrough.
- Guarded sends refuse an incomplete block (`Theorem` without `QED`, …) and
  comment-only selections instead of wedging hol's filter.

### Editing
- Opt-in holabs ASCII→unicode insert abbreviations (`abbreviations = true`)
  and `:HolUnabbrev` for the reverse.

### Theorem search
- `hf` / `:HolFind` (by name, `DB.find`) and `hm` / `:HolMatch` (by term
  pattern, `DB.apropos`; visual mode seeds the selection) open an interactive
  search panel: a horizontal split with a labelled, editable query bar — type
  a query and press `<CR>` to run it, press `<CR>` on a result to insert that
  theorem's name at the cursor in the window you searched from, `q` to close.
  Results are `holterm`-highlighted. Implemented over the one-way transport by
  having the query write formatted results to a temp file that Neovim polls; a
  bad term pattern reports the error instead of hanging.

### Insert-mode completion
- Completion in `hol4script` buffers as an [nvim-cmp] source (optional
  dependency): a curated static vocabulary of HOL tactics/tacticals plus live
  theorem names snapshotted from the session's `DB.listDB()` (public only).
  With `completion.auto_setup` the source is registered and added to the
  `hol4script` filetype's cmp sources automatically, so the popup appears as
  you type; accepting a theorem inserts the bare name. Over the one-way
  transport the theorem cache is refreshed when a REPL starts, after `hl`, and
  via `:HolCompletionRefresh` (an async temp-file round-trip); the tactic
  vocabulary is always available. `:HolCompletionToggle` switches it off/on;
  `completion.{enabled,tactics,theorems}` configure it.

[nvim-cmp]: https://github.com/hrsh7th/nvim-cmp

### Syntax highlighting
- **regex tier** (`syntax/hol4script.vim`): a verbatim port of upstream; zero
  build requirements; the automatic fallback.
- **tree-sitter tier** (preferred, built by `make parsers` / the spec's
  `build` hook; no nvim-treesitter needed): a new `holscript` grammar for
  script structure that fixes the regex tier's limits — indented blocks
  highlight, mismatched quote delimiters are errors, edits reparse
  incrementally, and folds cover `Definition`/`Datatype`/`Inductive` as well
  as `Proof..QED`. Block interiors are injected into real grammars: plain ML
  and tactics into vendored tree-sitter-sml, and term bodies + quotation
  interiors into a new lenient `holterm` grammar.

### Diagnostics & docs
- `:checkhealth hol4nvim` reports every discovery step (hol, holdir,
  holdeptool, vimhol.sml, fifo, tree-sitter parsers, nvim-cmp + completion
  cache size), naming the exact `setup()` option on failure, and flags a
  keymap `prefix`/leader collision that would force a `timeoutlen` delay.
- `:help hol4nvim` (`doc/hol4nvim.txt`).

### Filetype
- Ships `ftdetect/hol4script.lua`: `*Script.sml` → `hol4script`, taking
  precedence over the built-in `*.sml` → `sml` while leaving plain SML alone.
  Compatible with `ft = "hol4script"` lazy-loading.

[Unreleased]: https://github.com/artisanbk/hol4nvim/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/artisanbk/hol4nvim/releases/tag/v0.1.0
