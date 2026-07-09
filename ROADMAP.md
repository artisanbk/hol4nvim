# hol4nvim roadmap

Goal: a **standalone** lazy.nvim plugin for using HOL4 from Neovim (this repo
is not destined for the HOL source tree), with **full parity** with HOL4's
upstream `tools/editor-modes/vim/` config as the baseline: a HOL4 user
switching from the upstream vim setup loses no mapping, command, or syntax
behaviour. Beyond parity, the plugin should be **out of the box**: no
hand-edited dotfiles or environment plumbing — anything the upstream vim
setup makes you configure by hand becomes either automatic or a `setup()`
option in the user's lazy spec (see Phase 7).

Upstream reference (HOL4 source tree):

-   `hol.vim` --- REPL management + all proof transforms and proof-manager
    commands
-   `holabs.vim` --- Unicode input abbreviations + reverse (`HOLUnab`)
-   `hol4script.vim` --- syntax highlighting (HOL terms vs ML)
-   `filetype.vim` --- `*Script.sml` detection

## Architecture (keep this shape)

-   `transform.lua` --- the **what to send** layer: pure `string -> string`
    reshapers (expand, goal, subgoal, ...). No plugin dependencies; never in a
    require cycle.
-   `repl.lua` --- the **how to send** layer: terminal vs fifo transport,
    `auto` routing, session stack, HOL discovery. Holds `M.config`.
-   `fifo.lua` --- fifo transport for an external HOL session (Vimhol
    `ReadFile`).
-   `init.lua` (module) --- public `setup(opts)` + user commands.
-   `ftplugin/hol4script.lua` --- buffer-local keymaps/options.
-   `ftdetect/hol4script.lua` --- filetype detection.

This is already an improvement over upstream, which hard-splits the terminal
path (`hw`) from the fifo path (`hs` and the `HOLCall` C-channel). Here a
single `send()` picks the transport, so every transform and command routes
through it.

Other deliberate divergences from upstream:

-   `send()` refuses an incomplete script block (`Theorem` without `QED`,
    `Definition` without `End`, ...) with a warning. Upstream sends it raw,
    which wedges hol's filter at its `#` continuation prompt and silently eats
    the next send (Ctrl-C in the terminal recovers).
-   Send-style maps strip SML `(* ... *)` comments (nesting- and string-aware)
    before sending, and refuse comment-only selections. A selection whose
    comments never close (unbalanced inner `(*`) is refused with the offending
    line number instead of surfacing as a bogus missing-QED warning. Multi-line
    comments can contain `Theorem`/`QED`-looking lines that confuse hol's
    line-oriented filter mid-paste; upstream sends them raw.
-   `h!` / `:HolSendDocument` sends the whole buffer in one batch, dropping
    `open` declarations (they fail interactively for unloaded theories; `hl`
    covers them). No upstream equivalent.
-   The terminal transport auto-routes MULTI-LINE sends through the session's
    own Vimhol pipe (tempfile + `ReadFile`, i.e. `QUse.use` script parsing)
    when a reader is attached, falling back to raw pty input otherwise. Raw pty
    batches glue `;`-less statements and can wedge hol's filter at `#`;
    upstream avoids this only by hard-splitting `hs` (fifo) from `hw` (pty).
-   Visual selections are read live via `getregion()` while visual mode is
    still active; upstream's `:call` maps rely on `:` having exited visual mode
    first.

## Status legend

✅ done · 🟡 partial · ⬜ not started

## Current state

| Capability | Upstream | hol4nvim | Status |
|--------------------|--------------------|--------------------|--------------------|
| Filetype detection | `filetype.vim` | `ftdetect/hol4script.lua` | ✅ |
| REPL open / close | `hx` / `hX` | `repl.open` / `repl.close` | ✅ |
| HOL discovery (lastmaker/\$HOLDIR) | `WhichHOL` | `which_hol` | ✅ |
| Session stack + prune on exit | `g:hol_repl` | `M.sessions` | ✅ |
| Dual transport (terminal + fifo) | split mappings | `transport="auto"` | ✅ (better) |
| Send raw line / selection | `hs` `hw` | `hs` (`hw` alias) | ✅ |
| Quiet send | `hu` | `hu` (`transform.quiet`) | ✅ |
| Send whole document | --- | `h!` / `:HolSendDocument` (opens and new-style `Theory`/`Ancestors`/`Libs` headers dropped -- their interactive meaning is opens of possibly-unloaded theories, i.e. `hl` territory) | ✅ (extension) |
| Expand tactic | `he` | `he` (strips `>>`/`THEN`/`\\`/`by`... at the ends) | ✅ |
| Set goal | `hg` | `hg` (`transform.goal`) | ✅ |
| Unquoted goal | `hG` | `hG` (`transform.uqgoal`; Proof\[attrs\] + Resume headers) | ✅ |
| Subgoal | `hS` | `hS` (`transform.subgoal`) | ✅ |
| Suffices | `hF` | `hF` (`transform.suffices`) | ✅ |
| Pattern goal | `hP` | `hP` (`transform.pattern`, same token-stripping) | ✅ |
| Load deps | `hl` | `hl` (loads + quiet exec of selection + "completed"); new-style `Theory`/`Ancestors`/`Libs` headers work — holdeptool maps Ancestors to `<x>Theory` and Libs verbatim (verified against Trindemossen holdeptool) | ✅ |
| Multi-line via tempfile + fifo | `hs` (HOLCEnd) | terminal transport auto-routes multi-line sends through the session's Vimhol pipe | ✅ |
| Proof-manager controls | `hb hB hv hd hp hr hR hc` | same letters; counts repeat b/B/d, count is R's arg | ✅ |
| Selection helpers | `ht hT ha` | `hol4nvim/select.lua`, same letters | ✅ |
| Display toggles | `hy hn` | `repl.toggle_types` / `repl.toggle_unicode` | ✅ |
| Unicode abbreviations | `holabs.vim` (opt-in) | `hol4nvim/abbrev.lua`, `abbreviations = true` + `:HolUnabbrev` | ✅ |
| Syntax highlighting | `hol4script.vim` | `syntax/hol4script.vim` (5a regex fallback) + `holscript` tree-sitter grammar (5b: script structure, indented blocks, matched quote delimiters, incremental reparse) + injections (5c: SML into ML/tactics, `holterm` into terms/quotations) | ✅ |
| Theorem search | --- | `hf` `hm` / `:HolFind` `:HolMatch` (`search.lua`): `DB.find` name + `DB.apropos` term search in an interactive panel | ✅ (Phase 8) |
| Insert-mode completion | --- | `completion.lua` + `cmp.lua`: nvim-cmp source of static HOL tactics + live theorem names (`DB.listDB`), refreshed off `HolReplStarted`/`HolLoaded`; `:HolCompletionToggle` / `:HolCompletionRefresh` | ✅ (Phase 9) |
| External-session auto-setup | --- | `:HolExternalSetup` (`repl.write_hol_config` / `repl.write_shell_rc`): generates a machine-agnostic `$HOL_CONFIG` loader in the data dir and appends a managed `export` block to your shell rc (`$SHELL`-derived or `shell_rc`) so a hol you start yourself attaches Vimhol to the fifo — chains your own hol-config first, guarded so no double-tail; no `~/.hol-config.sml` written | ✅ (Phase 10) |

Test infrastructure (not an upstream feature, but load-bearing here):
`make test` = `tests/unit.lua` (HOL-free: ftdetect, commands, transforms,
fifo.path priority, keymaps) + `tests/e2e.lua` (drives a real hol REPL in a
`:terminal`). Two example files: `examples/TestScript.sml` is the guided keymap
tour (deliberately bare fragments --- NOT batch-sendable) and
`examples/WholeScript.sml` is the linear `h!`/whole-file-send demo; the e2e
drives both.

## Phases

### Phase 0 --- Foundation & cleanup ✅

-   [x] `lua/hol4nvim/keymaps.lua` is now the single keymap registry
    (data-driven spec table + `attach()`); `ftplugin/hol4script.lua` just calls
    it.
-   [x] Keymap scheme reconciled with upstream letters. Intentional divergence:
    upstream's `hw` (terminal send) and `hs` (fifo send) collapse into one
    transport-agnostic send on `hs`, with `hw` kept as an alias.
-   [x] `config` surface settled and documented in README (hol_cmd, split,
    start_insert, transport, fifo, keymaps, prefix).

### Phase 1 --- Proof transforms (highest daily value)

Pure additions to `transform.lua`, each wired to a keymap + routed through
`send()`. - \[x\] `hg` goal --- `proofManagerLib.g(...)` (strips trailing
commas/whitespace) - \[x\] `hS` subgoal ---
`proofManagerLib.expand(bossLib.sg(...))`, strips trailing `by ...` - \[x\]
`hF` suffices --- `proofManagerLib.expand(bossLib.qsuff_tac(...))`, strips
`suffices_by ...` - \[x\] `hP` pattern ---
`proofManagerLib.expand_list(Q.SELECT_GOAL_LT(...))` (token-stripping deferred
to Phase 3, same as `he`) - \[x\] `hG` unquoted goal --- statement +
`Proof[attrs]` lines via `proofManagerLib.new_goalstack` /
`BasicProvers.mk_tacmod`, and `Resume <thm>[<label>]:` headers via
`markerLib.set_suspended_goal`

Phase 1 complete ✅

### Phase 2 --- Proof-manager control commands

Thin `repl.lua` wrappers sending literal `proofManagerLib.*` strings via
`send()`. - \[x\] `hb` backup · `hB` restore · `hv` save · `hd` drop · `hp` p()
· `hr` restart (a count repeats b/B/d, upstream HOLRepeat semantics) - \[x\]
`hR` rotate --- honours a count (`v:count1`) - \[x\] `hc` Interrupt ---
"Interrupt" line to the session's Vimhol pipe, else the global fifo, else
CTRL-C into the pty (SIGINT; beyond upstream)

Phase 2 complete ✅

### Phase 3 --- Send refinements

-   [x] `hu` quiet send --- wrap in `HOL_Interactive.toggle_quietdec()` toggles
-   [x] Expand/pattern token-stripping --- leading/trailing
    `THEN[1L]`/`>>`/`>>~`/ `\\`/`>-`/`>|`/`>~`/`++`/`<<`/`by`/`,`/brackets are
    stripped (port of `s:strip*`), so `he` on a whole `>> tac` proof line just
    works
-   [x] Full `hl` load parity --- loads, then the selection itself executed
    inside quietdec toggles, then a `HOLLoad ... completed` confirmation print

Phase 3 complete ✅

### Phase 4 --- Editing ergonomics

-   [x] Unicode abbreviations from `holabs.vim` (`/\→∧`, `==>→⇒`, `!→∀`, ...)
    --- `lua/hol4nvim/abbrev.lua`, opt-in via `abbreviations = true` (upstream
    is opt-in too: you source holabs.vim yourself)
-   [x] `:HolUnabbrev` command --- reverse Unicode → ASCII (port `HOLUnab`;
    range-aware, defaults to the whole buffer where upstream is per-line)
-   [x] Selection-movement helpers (`lua/hol4nvim/select.lua`): `ht`
    single-quote term, `hT` double-quote term, `ha` Theorem...Proof block
    (feeds `hG`)
-   [x] Toggles: `hy` `Globals.show_types`, `hn` `PP.avoid_unicode`
-   [x] Upstream's `no \h h` passthrough mapping (so `hh` moves left when
    `<localleader>` is `h`, the vimhol docs' convention).

Phase 4 complete ✅

### Phase 5 --- Syntax highlighting

Progressive enhancement: regex parity ships first and stays as the fallback;
tree-sitter is the upgrade path. No tree-sitter grammar for HOL4 scripts
exists anywhere, so 5b/5c mean writing one --- kept small via injections.
Self-containment at every tier: one lazy.nvim spec, no nvim-treesitter
dependency (Neovim core `vim.treesitter` reads `parser/` and `queries/`
straight off the plugin's runtimepath).

-   [x] **5a --- regex parity (fallback tier)**: `syntax/hol4script.vim`, a
    verbatim port of upstream. Zero build requirements; its limitations
    (inherited from upstream, unchanged) are documented in the README.
-   [x] **5b --- skeleton `holscript` tree-sitter grammar**: parses ONLY the
    script-level structure --- `Theorem/Triviality ... Proof ... QED`,
    `Definition/Termination/End`, `Datatype`, `(Co)Inductive`,
    `Type`/`Overload`, quotations (`` ` ``, ` `` `, `‘’`, `“”`), `«»`
    strings, nested `(* *)` comments --- leaving everything between as
    opaque `ml_chunk` nodes. Detailed plan below; deltas when it landed:
    new-style `Theory`/`Ancestors`/`Libs` headers joined the scope (their
    `section_names` lists are a scanner token using the same
    indented-continuation shape as `h!`'s header dropper); `attributes`
    became an external token too (an internal regex loses to the chunk
    externals right after `Proof`); generated at ABI 14 so Neovim 0.10
    loads it; mismatched quote delimiters surface as a bounded
    `quotation_mismatched` node (queried as `@error`) rather than an
    unbounded parse error. 21 corpus tests (`make test-grammar`) + 19
    Neovim-side checks (`make test-ts`, in `make test`).
-   [x] **5c --- injections**: every opaque span from the 5b skeleton now
    hands its interior to a real grammar (all best-effort --- a missing
    `parser/<lang>.so` just leaves that span opaque):
    - `ml_chunk` (plain ML between blocks) and `tactic_chunk` (tactics are
      SML) → vendored [tree-sitter-sml](https://github.com/MatthewFluet/tree-sitter-sml)
      (`grammar/sml/`, MIT, commit `558bf67`, regenerated at ABI 14; see
      `grammar/sml/PROVENANCE.md`);
    - `term_chunk` (Definition/Datatype/Inductive bodies) and quotation
      interiors → `holterm` (`grammar/holterm/`), a new lenient token-stream
      grammar for the HOL term language (binders, operators, `if/then/else`,
      `T`/`F`, numbers, strings, type vars, `^` antiquotation, nested
      comments). It is deliberately NOT a real expression parser: HOL's
      concrete term grammar is user-extensible, so a token stream that never
      errors is both the correct and the sufficient design for highlighting.

    Landed deltas from the plan: quotations split into three node types by
    delimiter WIDTH (`quotation_single` 1-byte, `quotation_double` 2-byte,
    `quotation_unicode` 3-byte) so `injections.scm` trims delimiters with a
    fixed per-node `#offset!` --- keeping the holscript scanner stateless
    rather than emitting separate delimiter/content tokens. 12 holterm corpus
    tests + 14 new Neovim-side injection checks (`tests/treesitter.lua`, now
    33), both example files parse with zero ERROR nodes across all three
    languages.

    Stretch (still open, tracked for later): SML injection into `^(..)`
    antiquotations; register the grammars with nvim-treesitter's community
    registry; TS folds/textobjects; reimplement `ha ht hT` on tree nodes
    instead of regex searches.

Phase 5 complete ✅ (5c stretch items deferred, listed above)

#### 5b plan

Editor integration already landed with 5a: `ftplugin/hol4script.lua` does
`vim.treesitter.language.register("holscript", "hol4script")` +
`pcall(vim.treesitter.start)`, so the parser lights up the moment
`parser/holscript.so` exists and the regex tier keeps serving until then.

Layout (everything on the plugin's own rtp; Neovim core picks up `parser/`
and `queries/` with no nvim-treesitter):

    grammar/holscript/grammar.js      -- grammar source (maintainer-edited)
    grammar/holscript/src/parser.c    -- generated, VENDORED (committed)
    grammar/holscript/src/scanner.c   -- external scanner (hand-written)
    grammar/holscript/test/corpus/    -- tree-sitter native corpus tests
    parser/holscript.so               -- built artifact, gitignored
    queries/holscript/{highlights,folds,injections}.scm

Toolchain split: regenerating `parser.c` from `grammar.js` needs the
tree-sitter CLI (`make grammar`, maintainer-only); users compile the
vendored C with nothing but `cc` (`make parsers` ==
`cc -shared -fPIC -o parser/holscript.so src/parser.c src/scanner.c`,
invoked by the lazy spec's `build` hook).

The external scanner owns the three context-sensitive tokens:

-   nested `(* *)` comments (regex-impossible; same approach as OCaml's
    grammar);
-   quotation delimiters --- distinguishing `` ` `` from ` `` ` needs
    two-char lookahead, and close must MATCH open (`` `x + y’ `` becomes an
    error node instead of the regex tier's silent "well-formed" rendering);
-   block keywords (`Theorem`, `Definition`, ...) recognised at line start
    --- after optional whitespace, fixing the regex tier's column-0-only
    limitation (an indented `Theorem foo:` highlights) while `val Theorem =`
    mid-line still lexes as plain ML.

Grammar shape: `source_file = repeat(theorem_block | definition_block |
datatype_block | inductive_block | type_abbrev | overload_decl | quotation |
hol_string | comment | ml_chunk)`; block interiors are `term_text` /
`tactic_text` opaque spans (5c injects into them), `ml_chunk` absorbs
everything else. Incremental parsing replaces `syn sync fromstart`, killing
the whole-file-rescan lag on big Script files.

Queries: `highlights.scm` maps to standard captures only (`@keyword`,
`@comment`, `@string`, `@punctuation.bracket`, `@function` for theorem
names, `@attribute` for `[attrs]`) so every colorscheme works; `folds.scm`
folds `Proof..QED` AND `Definition/Datatype/Inductive..End` (regex tier
only folds the former); `injections.scm` ships as a stub wired up in 5c.

Test tiers: (1) `grammar/holscript/test/corpus/` snapshots run by the
tree-sitter CLI --- fast dev loop, no Neovim; (2) a new HOL-free
`tests/treesitter.lua` (in `make test` behind a parser-built guard,
skipping with a notice when unbuilt) asserting parse trees on
`examples/*.sml` plus targeted snippets --- indented Theorem, mismatched
quote delimiters (error node), nested comments, `Termination` split ---
and highlight captures at positions, mirroring the regex syntax
assertions already in `tests/unit.lua`.

Sequencing:

1.  Scaffold `grammar/holscript/` + Makefile targets (`grammar`,
    `parsers`) + gitignore the `.so`; empty grammar parses everything as
    `ml_chunk`.
2.  Scanner: nested comments, the three quotation pairs, `«»`/`""`
    strings, line-start block keywords; corpus tests per token.
3.  Blocks, one rule at a time with corpus tests: Theorem/Triviality
    (incl. `[attrs]`, `Proof[attrs]`), Definition/Termination/End,
    Datatype, (Co)Inductive, Type/Overload.
4.  Vendor `parser.c`; write the queries (highlights, folds, injection
    stub).
5.  `tests/treesitter.lua` + `make test` wiring; verify live against
    `examples/TestScript.sml` with `:InspectTree`.
6.  README: update the syntax section (build hook, what the TS tier
    fixes); tick 5b here.

### Phase 6 --- Polish & release

The last phase: make the plugin diagnosable, documented in-editor, and
tagged. No new user-facing behaviour --- everything here reports on or
packages what Phases 0--7 already built. Detailed plan below.

-   [x] **6a --- `:checkhealth hol4nvim`** (`lua/hol4nvim/health.lua`):
    surfaces every discovery step (hol binary, holdir, holdeptool,
    vimhol.sml, fifo transport, tree-sitter parsers) by re-running the
    plugin's own resolvers, naming the exact `setup()` option on each
    failure; plus the one setup mistake that already bit a real user ---
    a keymap `prefix` equal to the leader with a longer global map sharing
    it, which forces the `timeoutlen` wait (the pure `M.prefix_collisions`
    is unit-tested). Tests: 6 HOL-free checks in `tests/unit.lua` (stubbed
    `vim.health`) + the deferred 7d "config pre-loads Vimhol" smoke
    graduated into the e2e tier as `tests/e2e_preload.lua` (sentinel still
    prints, guard no-ops, pipe-routed send evaluates exactly once).
-   [x] **6b --- `:help hol4nvim`** (`doc/hol4nvim.txt` + committed
    `doc/tags`): vimdoc port of the README (intro, requirements, install,
    the full config surface as `*hol4nvim-opt-*` tags, the mapping table as
    `*hol4nvim-\<key>*` tags, commands, the two syntax tiers, transport, a
    `:checkhealth` section, and troubleshooting). README stays the source of
    truth; CLAUDE.md notes the drift guard.
-   [~] **6c --- release**: `CHANGELOG.md` written (0.1.0, grouped by
    capability) and the published spec reconciled (`examples/user-init.lua`
    now carries `build = "make parsers"` like the README block). Remaining:
    commit the outstanding tree (5c + 6a/6b) and cut the annotated tag once
    `make test` is green.
-   [x] README with install spec, config defaults, mapping table
-   [x] Tests --- `make test`: unit tier (HOL-free) + e2e tier (live REPL);
    extend both as each phase lands

#### 6a plan --- `:checkhealth hol4nvim`

A `health.lua` with `M.check()`, registered by Neovim's convention
(`require("hol4nvim.health").check()` runs on `:checkhealth hol4nvim`; no
wiring needed beyond the file existing on the rtp). Uses the `vim.health`
API (`start`/`ok`/`warn`/`error`/`info`). It re-runs the same resolvers the
plugin uses at runtime --- no duplicated logic --- and, crucially, whenever
a step fails it names the exact `setup()` option to set (the 7d/7b promise:
"naming the exact missing `setup()` option whenever a discovery step
fails"). Sections:

-   **hol binary** --- `repl.which_hol()`. `ok` with the resolved path and
    how it was found (config.hol_cmd / config.holdir / lastmaker / $HOLDIR /
    $PATH), or `error` naming `hol_cmd`/`holdir`.
-   **holdir** --- `repl.holdir()`. Report the root and its derivation;
    `warn` (not error) when only `$HOLDIR` supplied it, since that is the
    fallback Phase 7 tries to retire.
-   **holdeptool** (`hl`) --- probe `holdeptool.exe` next to the hol binary
    then under `holdir()/bin`; `warn` if absent (only `hl` needs it).
-   **vimhol.sml** (`hx` bootstrap) --- `repl.vimhol_sml()`; `ok`/`warn`
    with the resolved path, `info` when `vimhol = false` (auto-bootstrap
    disabled by choice).
-   **fifo transport** --- `fifo.path()`; report the resolved path, whether
    it exists as a fifo, whether the dir is writable, and whether a reader
    is currently attached (mirrors the `hs` no-reader check). `info` the
    active `transport` setting.
-   **tree-sitter tier** --- for `holscript`/`holterm`/`sml`, whether
    `parser/<lang>.so` loads; `ok` (TS tier active) or `warn` (regex
    fallback --- tell them to run `make parsers` / add `build = "make
    parsers"`). Also flag ABI/Neovim-version mismatch if `language.add`
    fails for a built parser.
-   **keymap prefix vs leader** --- the bug that actually cost a user 800ms
    on `hs`/`he`. When `config.prefix` equals `mapleader`/`maplocalleader`,
    scan existing global maps (`nvim_get_keymap`) for entries that start
    with `prefix` and are longer than `prefix .. <suffix>`; any such
    overlap makes Neovim wait `timeoutlen` on every hol map. `warn` listing
    the colliding lhs's and the two fixes (raise `timeoutlen`, or change
    `prefix` off the leader). This is the one health check that encodes
    hard-won project knowledge rather than restating discovery. See
    [[user-nvim-config]].

Tested HOL-free in `tests/unit.lua`: drive `health.check()` with a stub
`vim.health` collecting `{level, msg}` tuples, assert the collision warning
fires for `prefix=" "` with a planted overlapping global map and stays
silent otherwise, and that a missing-hol config produces an `error` naming
`hol_cmd`/`holdir`. Also fold in here the 7d deferral: the standalone
"config pre-loads Vimhol" smoke script (bootstrap no-ops, sentinel still
prints, one pipe-routed eval) graduates into the e2e tier now that a second
hol boot is acceptable at release time.

#### 6b plan --- `:help hol4nvim`

`doc/hol4nvim.txt` in vimdoc format (`*hol4nvim.txt*` header, `*tag*`
anchors, `>`/`<` code blocks, a modeline `vim:tw=78:ts=8:ft=help:norl:`),
plus a `doc/tags` generated by `:helptags doc/` (committed so `:help`
works without the user regenerating). Content is the README reorganised for
in-editor lookup, not new prose: install/spec, the full config table with
defaults, the keymap table (`*hol4nvim-mappings*`), the command list, the
two syntax tiers, and a troubleshooting section that points at
`:checkhealth hol4nvim`. Keep it in sync with README by treating README as
source and the helpdoc as its vimdoc rendering; a `make` target or a note
in CLAUDE.md guards against drift.

#### 6c plan --- release

-   Reconcile the three copies of the lazy spec (README install block,
    `examples/user-init.lua`, the user's own `~/.config/nvim/...`) so the
    published one carries `build = "make parsers"` and the documented
    defaults.
-   `CHANGELOG.md` covering Phases 0--7 as the initial release notes.
-   Tag (annotated, signed) once `make test` is green and the tree is
    committed; the published spec pins the tag.

### Phase 7 --- Out-of-the-box setup (standalone goal)

Upstream vimhol makes the user hand-wire things outside the editor. Full
audit of those requirements and their hol4nvim disposition:

| Upstream asks you to hand-wire | hol4nvim | Status |
|---|---|---|
| `~/.hol-config.sml` that `use`s `vimhol.sml` (enables the fifo protocol: pipe transport, `hc` interrupt, robust multi-line sends) | 7a auto-bootstrap at `hx` | ✅ |
| `$HOLDIR` environment variable (holdeptool for `hl`, default fifo path, vimhol.sml location) | 7b `holdir()` resolver + `holdir` option | ✅ |
| `hol` on `$PATH` | `hol_cmd` / lastmaker / `$HOLDIR` discovery chain | ✅ (Phase 0) |
| copy `filetype.vim` into `~/.vim` | `ftdetect/` ships in-plugin; compatible with `ft = "hol4script"` lazy-loading (lazy.nvim sources plugin ftdetect eagerly, so `*Script.sml` detection precedes the plugin's own load — verified headless: no load at startup or for plain `.sml`, full attach on first `*Script.sml`) | ✅ (Phase 0, lazy-load verified with the published spec) |
| copy `hol4script.vim` into `~/.vim/syntax` | `syntax/` ships in-plugin | ✅ (5a) |
| source `holabs.vim` by hand | `abbreviations = true` | ✅ (Phase 4) |
| `vimhol.sh` (tmux + rlwrap + per-pair fifo plumbing) | subsumed by `hx`: in-vim `:terminal` + per-session pipe | ✅ |
| `$VIMHOL_FIFO` env shared with an external session | `config.fifo` + the 7c no-reader recipe | ✅ |

End state: a fresh user adds the lazy spec, sets `holdir` only if their HOL
is not discoverable, and everything works --- no dotfiles, no exported
environment variables, nothing copied by hand.

-   [x] **7a --- auto-bootstrap Vimhol into spawned REPLs.** Right after
    `hx` spawns the terminal job, feed the pty (each line a complete
    statement --- this cannot go through `send()`: the pipe it enables is
    not up yet):

        val _ = case #lookupStruct PolyML.globalNameSpace "Vimhol" of
                  NONE => use "<holdir>/tools/editor-modes/vim/vimhol.sml"
                | SOME _ => ();
        val _ = print "hol4nvim: vimhol readyhn";

    wrapped in quietdec toggles to keep the banner clean. No timing games
    needed: hol evaluates stdin only after `check-intconfig.sml` has run
    any `~/.hol-config.sml` / `$HOL_CONFIG`, so the guard always observes
    whether the user's own config loaded Vimhol and no-ops instead of
    attaching a second tail to the pipe (guard validated against
    Trindemossen 2 with and without a config). The sentinel print is the
    deterministic ready signal for users and the e2e boot wait.
    Config: `vimhol = true` (default) `| false | "/path/to/vimhol.sml"`;
    discovery is `<holdir()>/tools/editor-modes/vim/vimhol.sml` (plus the
    pre-rename `tools/vim/` for older installs). The generated vimhol.sml
    is location-independent for us: its baked-in fifo path is only the
    `$VIMHOL_FIFO`-unset fallback, and `repl.open` always exports a
    per-session `VIMHOL_FIFO`. If the file cannot be found, warn once and
    continue --- the session still works, with multi-line sends and `hc`
    degrading to the raw pty exactly as they do today without the dotfile.
-   [x] **7b --- single `holdir()` resolver.** Order: `config.holdir` →
    derived from the resolved hol binary (`.../bin/hol`, resolved through
    `$PATH` and symlinks, two dirs up, accepted when a `tools/` sibling
    confirms a HOL tree --- covers lastmaker and `hol_cmd` too) → `$HOLDIR`
    demoted to last-resort fallback. `holdeptool()` and `fifo.path()`'s
    default now route through it (7a discovery will too). One
    `holdir = "..."` line in the lazy spec (or nothing at all when hol is
    discoverable) configures everything; the README setup section no longer
    asks for environment variables. The derivation also runs in reverse:
    `which_hol()` consults `<config.holdir>/bin/hol` ahead of `$HOLDIR`
    and `$PATH`, so `holdir` alone selects the REPL binary too (gap found
    while writing `examples/user-init.lua`).
-   [x] **7c --- external-session recipe.** The fifo transport targets a
    HOL the plugin did not spawn, so it cannot bootstrap it --- instead the
    failure is actionable: the "no fifo reader" warning names the resolved
    fifo path and the exact paste-able recipe (`repl.external_recipe()`:
    `VIMHOL_FIFO='<path>' hol` plus the guarded `use` line, or a
    placeholder when vimhol.sml is unresolvable), and creates the fifo if
    absent (vimhol creates it too; both sides tolerate it existing --- a
    non-fifo in the way is named instead). Recipe validated verbatim: an
    external piped hol given exactly those two lines attaches, and a
    session-less Neovim's multi-line send evaluates in it. (Gotcha for
    humans watching such a session: a PIPED hol keeps vimhol's
    `print_depth 0`, so value echoes are invisible --- interactive/pty
    sessions print normally.)
-   [x] **7d --- prove it in tests** (landed with 7a). The e2e tier used to
    be green only because the development machine's `~/.hol-config.sml`
    loads vimhol --- exactly the dependence Phase 7 abolishes. The e2e REPL
    now boots with `HOL_NOCONFIG=1` and waits on the `hol4nvim: vimhol
    ready` sentinel (replacing the "Use-ing configuration" needle), so
    every pipe-routed multi-line send, `hc` interrupt, and `hl` in the
    suite runs on the plugin's own bootstrap with zero dotfiles. The
    guard's other branch --- a config that pre-loads Vimhol: bootstrap
    no-ops, the sentinel still prints, and a pipe-routed probe evaluates
    exactly once --- is verified by a standalone smoke script; folding that
    into the suite costs a second hol boot, deferred to Phase 6 polish
    alongside `:checkhealth hol4nvim` naming the exact missing `setup()`
    option whenever a discovery step fails.

-   [x] **7e --- forgiving path options.** A spec written from memory says
    `hol_cmd = "~/HOL/bin/"`: `setup()` expands `~` in the path-like
    options (`hol_cmd`, `holdir`, `fifo`, string `vimhol`) since
    jobstart/filereadable take it literally, and `which_hol()` accepts a
    directory (the `bin/` or the HOL root) by finding `hol`/`bin/hol`
    inside it. A fresh `lazy.nvim` install straight from GitHub with
    exactly such a spec was verified headless end-to-end (isolated XDG
    dirs: clone, no load at startup, detection + attach on `*Script.sml`).

Phase 7 complete ✅

### Phase 8 --- Theorem search

-   [x] **Search panel** (`lua/hol4nvim/search.lua`): query the live
    session's theorem database from an interactive panel, rather than
    scrolling the REPL. `hf`/`hm` (or `:HolFind`/`:HolMatch`) open a
    horizontal split of the focused window whose first line names the search
    type, second line is an editable query bar, and the rest the results;
    `<CR>` on the bar runs the query (editing it and pressing `<CR>` again
    re-runs), `<CR>` on a result line inserts that theorem's name at the cursor
    in the window the panel was opened from (and yanks it), `q` closes. `hf`
    searches names (`DB.find`); `hm` searches by term pattern (`DB.apropos`,
    parsing with `Parse.Term`), and in visual mode seeds the bar with the
    selection. The bar starts pre-filled with `<cword>`.

    Key design point: the plugin's transport is one-way (send only; see the
    Architecture note), so there is no channel to read HOL's answers back.
    Instead the query is pure SML that FORMATS the hits (`Parse.thm_to_string`)
    and writes them to a temp file ending in a `===HOLSEARCH_DONE===`
    sentinel; Neovim polls the file and renders it. Formatting the string
    ourselves sidesteps the `print_depth 0` echo suppression on piped
    sessions. The whole query is wrapped in a handler that ALWAYS writes the
    sentinel, so a term pattern that fails to parse reports the error instead
    of hanging the poll. Results are `holterm`-highlighted (the unicode
    `⊢ ∀ ∧ ⇒` become real operators/binders), reusing the 5c grammar.

    The SML builder is pure `(query, outfile) -> string`, unit-tested like
    `transform.lua`; a live name search (`DB.find "ASSOC"` -> `ADD_ASSOC`)
    is asserted in the e2e tier. Gotcha recorded: internal SML bindings must
    be letter-first (`hnv_*`), since a leading `_` is the wildcard, not an
    identifier. Deferred: `DB.match`/theory-scoped search, result-line jumps
    to source, a float layout.

Phase 8 complete ✅

### Phase 9 --- Insert-mode completion

-   [x] **Completion source** (`lua/hol4nvim/completion.lua` +
    `lua/hol4nvim/cmp.lua`): insert-mode completion in `hol4script` buffers,
    exposed as an nvim-cmp source. Two vocabularies feed it: a curated static
    list of HOL tactics/tacticals (`M.TACTICS`, offline, no REPL), and theorem
    names snapshotted from the live session's `DB.listDB()` (public only,
    filtered on `thminfo.private`). `completion.register()` registers the
    `hol4nvim` source and, with `auto_setup`, prepends it to the `hol4script`
    filetype's cmp sources (merged with the user's own), so with nvim-cmp
    installed it works out of the box. Accepting a theorem inserts the bare
    name, matching the search panel's pick.

    Same one-way-transport constraint as search: theorem names can't be
    queried per keystroke, so `M.refresh()` sends a single-line enumeration
    SML that writes `name<TAB>theory` lines to a temp file ending in a
    `===HOLCOMPLETE_DONE===` sentinel, polled *asynchronously* (a libuv timer,
    not `vim.wait`, so a background refresh never blocks the UI). The command
    is one line so it goes straight to the pty and never needs the Vimhol pipe
    (which may not be attached yet just after a REPL starts). Refreshes are
    driven by `User` autocmds `repl` fires --- `HolReplStarted` after the
    bootstrap, `HolLoaded` after `hl` --- so `repl` needs no dependency on
    `completion`; plus a lazy refresh on first completion and
    `:HolCompletionRefresh`. `completion.enabled` (flipped by
    `:HolCompletionToggle`) gates the source's `is_available`, so it toggles
    without touching the user's cmp config.

    The enumeration builder and parser are pure and unit-tested; a live
    refresh finding `ADD_ASSOC` is asserted in the e2e tier. `:checkhealth`
    reports nvim-cmp presence and the cache size. Deferred: constant-name
    completion (`Theory.constants`), context-awareness (tactics only inside
    `Proof..QED`, theorems only inside `rw[..]`) via the tree-sitter tier, a
    native blink.cmp source (blink can consume this one via `blink.compat`).

Phase 9 complete ✅

### Phase 10 --- External-session auto-setup

-   [x] **`:HolExternalSetup`** (`repl.write_hol_config` /
    `repl.external_env`, driven from `init.lua`): makes a hol you start
    yourself in a terminal (not the `hx` in-vim REPL) attach to the Vimhol
    fifo out of the box. The plugin can't inject into a process it didn't
    spawn, so instead it writes a loader that hol's own config mechanism picks
    up: pointing `$HOL_CONFIG` at `stdpath("data")/hol4nvim/hol-config.sml`
    makes any hol attach Vimhol. The command writes the loader (also ensuring
    the fifo exists) and appends a **managed `export HOL_CONFIG=... /
    VIMHOL_FIFO=...` block** to the user's shell rc (`repl.write_shell_rc` /
    `repl.splice_rc`; fish gets `set -gx`). **No `~/.hol-config.sml` is
    created** --- the loader lives in Neovim's data dir (the user asked not to
    scatter dotfiles).

    The rc is derived from `$SHELL` (`~/.zshrc`, `~/.bashrc`, fish
    `config.fish`), overridable via the `shell_rc` option or a
    `:HolExternalSetup <path>` argument. Writing is **opt-in**: only the
    explicit command touches a shell rc --- never `setup()`. The block sits
    between markers so re-running rewrites it in place (idempotent, current
    paths) and deleting the block undoes it cleanly.

    The loader is **machine-agnostic** by construction: `$HOME` is read at
    hol-runtime (no home path baked in) and `vimhol.sml` is resolved from
    `$HOLDIR` at runtime, falling back to the path `vimhol_sml()` resolved when
    it was written. Because `$HOL_CONFIG` *replaces* hol's own
    `~/.hol-config.sml` search (`tools/check-intconfig.sml`), the loader runs
    the user's own hol-config first (in hol's exact `$HOME` search order), then
    attaches Vimhol --- guarded via `#lookupStruct` so a config that already
    loaded Vimhol is not loaded (and re-tailed) a second time. Regenerated on
    every `setup()` so it never goes stale.

    Deliberately does **not** set `vim.env.HOL_CONFIG` globally: that would
    silently reroute the proven `hx` config-loading for every user. The
    export/alias is opt-in; once added it applies to `hx` too, which is exactly
    why the loader chains the user's own config rather than replacing it.

    Also fixes the external recipe's `<HOLDIR>` placeholder: `vimhol_sml()`
    gains a fallback that looks beside the resolved fifo when `holdir()` can't
    be determined. The loader content/escaping and the fallback are unit-tested;
    `tests/e2e_external.lua` boots a real hol against the generated loader to
    prove the SML parses and attaches exactly one tail. `:checkhealth` reports
    the loader and whether `$HOL_CONFIG` points at it.

Phase 10 complete ✅

## Keep in view (not primary)

-   (nothing outstanding)

## Upstream mapping reference (`<LocalLeader>` = `h` by default)

    x new REPL      X close REPL     w/s send         u send quiet
    e expand        g goal           G unquoted goal  S subgoal
    F suffices      P pattern        l load deps
    R rotate        b backup         B restore        v save
    d drop          p p()            r restart        c interrupt
    t sel `term`    T sel ``term``   a sel Theorem    y show_types
    n avoid_unicode h h (passthru)
