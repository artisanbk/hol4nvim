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
path (`\w`) from the fifo path (`\s` and the `HOLCall` C-channel). Here a
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
-   `\!` / `:HolSendDocument` sends the whole buffer in one batch, dropping
    `open` declarations (they fail interactively for unloaded theories; `\l`
    covers them). No upstream equivalent.
-   The terminal transport auto-routes MULTI-LINE sends through the session's
    own Vimhol pipe (tempfile + `ReadFile`, i.e. `QUse.use` script parsing)
    when a reader is attached, falling back to raw pty input otherwise. Raw pty
    batches glue `;`-less statements and can wedge hol's filter at `#`;
    upstream avoids this only by hard-splitting `\s` (fifo) from `\w` (pty).
-   Visual selections are read live via `getregion()` while visual mode is
    still active; upstream's `:call` maps rely on `:` having exited visual mode
    first.

## Status legend

✅ done · 🟡 partial · ⬜ not started

## Current state

| Capability | Upstream | hol4nvim | Status |
|--------------------|--------------------|--------------------|--------------------|
| Filetype detection | `filetype.vim` | `ftdetect/hol4script.lua` | ✅ |
| REPL open / close | `\x` / `\X` | `repl.open` / `repl.close` | ✅ |
| HOL discovery (lastmaker/\$HOLDIR) | `WhichHOL` | `which_hol` | ✅ |
| Session stack + prune on exit | `g:hol_repl` | `M.sessions` | ✅ |
| Dual transport (terminal + fifo) | split mappings | `transport="auto"` | ✅ (better) |
| Send raw line / selection | `\s` `\w` | `\s` (`\w` alias) | ✅ |
| Quiet send | `\u` | `\u` (`transform.quiet`) | ✅ |
| Send whole document | --- | `\!` / `:HolSendDocument` (opens dropped) | ✅ (extension) |
| Expand tactic | `\e` | `\e` (strips `>>`/`THEN`/`\\`/`by`... at the ends) | ✅ |
| Set goal | `\g` | `\g` (`transform.goal`) | ✅ |
| Unquoted goal | `\G` | `\G` (`transform.uqgoal`; Proof\[attrs\] + Resume headers) | ✅ |
| Subgoal | `\S` | `\S` (`transform.subgoal`) | ✅ |
| Suffices | `\F` | `\F` (`transform.suffices`) | ✅ |
| Pattern goal | `\P` | `\P` (`transform.pattern`, same token-stripping) | ✅ |
| Load deps | `\l` | `\l` (loads + quiet exec of selection + "completed") | ✅ |
| Multi-line via tempfile + fifo | `\s` (HOLCEnd) | terminal transport auto-routes multi-line sends through the session's Vimhol pipe | ✅ |
| Proof-manager controls | `\b \B \v \d \p \r \R \c` | same letters; counts repeat b/B/d, count is R's arg | ✅ |
| Selection helpers | `\t \T \a` | `hol4nvim/select.lua`, same letters | ✅ |
| Display toggles | `\y \n` | `repl.toggle_types` / `repl.toggle_unicode` | ✅ |
| Unicode abbreviations | `holabs.vim` (opt-in) | `hol4nvim/abbrev.lua`, `abbreviations = true` + `:HolUnabbrev` | ✅ |
| Syntax highlighting | `hol4script.vim` | `syntax/hol4script.vim` (5a regex parity; tree-sitter 5b/5c pending) | 🟡 |

Test infrastructure (not an upstream feature, but load-bearing here):
`make test` = `tests/unit.lua` (HOL-free: ftdetect, commands, transforms,
fifo.path priority, keymaps) + `tests/e2e.lua` (drives a real hol REPL in a
`:terminal`). Two example files: `examples/TestScript.sml` is the guided keymap
tour (deliberately bare fragments --- NOT batch-sendable) and
`examples/WholeScript.sml` is the linear `\!`/whole-file-send demo; the e2e
drives both.

## Phases

### Phase 0 --- Foundation & cleanup ✅

-   [x] `lua/hol4nvim/keymaps.lua` is now the single keymap registry
    (data-driven spec table + `attach()`); `ftplugin/hol4script.lua` just calls
    it.
-   [x] Keymap scheme reconciled with upstream letters. Intentional divergence:
    upstream's `\w` (terminal send) and `\s` (fifo send) collapse into one
    transport-agnostic send on `\s`, with `\w` kept as an alias.
-   [x] `config` surface settled and documented in README (hol_cmd, split,
    start_insert, transport, fifo, keymaps, prefix).

### Phase 1 --- Proof transforms (highest daily value)

Pure additions to `transform.lua`, each wired to a keymap + routed through
`send()`. - \[x\] `\g` goal --- `proofManagerLib.g(...)` (strips trailing
commas/whitespace) - \[x\] `\S` subgoal ---
`proofManagerLib.expand(bossLib.sg(...))`, strips trailing `by ...` - \[x\]
`\F` suffices --- `proofManagerLib.expand(bossLib.qsuff_tac(...))`, strips
`suffices_by ...` - \[x\] `\P` pattern ---
`proofManagerLib.expand_list(Q.SELECT_GOAL_LT(...))` (token-stripping deferred
to Phase 3, same as `\e`) - \[x\] `\G` unquoted goal --- statement +
`Proof[attrs]` lines via `proofManagerLib.new_goalstack` /
`BasicProvers.mk_tacmod`, and `Resume <thm>[<label>]:` headers via
`markerLib.set_suspended_goal`

Phase 1 complete ✅

### Phase 2 --- Proof-manager control commands

Thin `repl.lua` wrappers sending literal `proofManagerLib.*` strings via
`send()`. - \[x\] `\b` backup · `\B` restore · `\v` save · `\d` drop · `\p` p()
· `\r` restart (a count repeats b/B/d, upstream HOLRepeat semantics) - \[x\]
`\R` rotate --- honours a count (`v:count1`) - \[x\] `\c` Interrupt ---
"Interrupt" line to the session's Vimhol pipe, else the global fifo, else
CTRL-C into the pty (SIGINT; beyond upstream)

Phase 2 complete ✅

### Phase 3 --- Send refinements

-   [x] `\u` quiet send --- wrap in `HOL_Interactive.toggle_quietdec()` toggles
-   [x] Expand/pattern token-stripping --- leading/trailing
    `THEN[1L]`/`>>`/`>>~`/ `\\`/`>-`/`>|`/`>~`/`++`/`<<`/`by`/`,`/brackets are
    stripped (port of `s:strip*`), so `\e` on a whole `>> tac` proof line just
    works
-   [x] Full `\l` load parity --- loads, then the selection itself executed
    inside quietdec toggles, then a `HOLLoad ... completed` confirmation print

Phase 3 complete ✅

### Phase 4 --- Editing ergonomics

-   [x] Unicode abbreviations from `holabs.vim` (`/\→∧`, `==>→⇒`, `!→∀`, ...)
    --- `lua/hol4nvim/abbrev.lua`, opt-in via `abbreviations = true` (upstream
    is opt-in too: you source holabs.vim yourself)
-   [x] `:HolUnabbrev` command --- reverse Unicode → ASCII (port `HOLUnab`;
    range-aware, defaults to the whole buffer where upstream is per-line)
-   [x] Selection-movement helpers (`lua/hol4nvim/select.lua`): `\t`
    single-quote term, `\T` double-quote term, `\a` Theorem...Proof block
    (feeds `\G`)
-   [x] Toggles: `\y` `Globals.show_types`, `\n` `PP.avoid_unicode`
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
-   [ ] **5b --- skeleton `holscript` tree-sitter grammar**: parses ONLY the
    script-level structure --- `Theorem/Triviality ... Proof ... QED`,
    `Definition/Termination/End`, `Datatype`, `(Co)Inductive`,
    `Type`/`Overload`, quotations (`` ` ``, ` `` `, `‘’`, `“”`), `«»`
    strings, nested `(* *)` comments --- leaving everything between as
    opaque `ml_chunk` nodes. Detailed plan below.
-   [ ] **5c --- injections**: `ml_chunk` + tactic regions → vendored
    tree-sitter-sml (degrades gracefully if unbuilt); quotation interiors →
    a new tiny `holterm` grammar (binders, operators, HOL keywords --- where
    tree-sitter clearly beats regex). Stretch: register the grammar with
    nvim-treesitter's community registry; TS folds/textobjects; reimplement
    `\a \t \T` on tree nodes instead of regex searches.

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

-   [ ] `:checkhealth hol4nvim` (hol/holdeptool/HOLDIR/fifo, transport sanity)
-   [x] README with install spec, config defaults, mapping table
-   [ ] `:help hol4nvim` doc
-   [x] Tests --- `make test`: unit tier (HOL-free) + e2e tier (live REPL);
    extend both as each phase lands
-   [ ] Tag a release; finalise the published lazy.nvim spec snippet

### Phase 7 --- Out-of-the-box setup (standalone goal)

Upstream vimhol makes the user hand-wire things outside the editor. Full
audit of those requirements and their hol4nvim disposition:

| Upstream asks you to hand-wire | hol4nvim | Status |
|---|---|---|
| `~/.hol-config.sml` that `use`s `vimhol.sml` (enables the fifo protocol: pipe transport, `\c` interrupt, robust multi-line sends) | 7a auto-bootstrap at `\x` | ✅ |
| `$HOLDIR` environment variable (holdeptool for `\l`, default fifo path, vimhol.sml location) | 7b `holdir()` resolver + `holdir` option | ✅ |
| `hol` on `$PATH` | `hol_cmd` / lastmaker / `$HOLDIR` discovery chain | ✅ (Phase 0) |
| copy `filetype.vim` into `~/.vim` | `ftdetect/` ships in-plugin; compatible with `ft = "hol4script"` lazy-loading (lazy.nvim sources plugin ftdetect eagerly, so `*Script.sml` detection precedes the plugin's own load — verified headless: no load at startup or for plain `.sml`, full attach on first `*Script.sml`) | ✅ (Phase 0, lazy-load verified with the published spec) |
| copy `hol4script.vim` into `~/.vim/syntax` | `syntax/` ships in-plugin | ✅ (5a) |
| source `holabs.vim` by hand | `abbreviations = true` | ✅ (Phase 4) |
| `vimhol.sh` (tmux + rlwrap + per-pair fifo plumbing) | subsumed by `\x`: in-vim `:terminal` + per-session pipe | ✅ |
| `$VIMHOL_FIFO` env shared with an external session | `config.fifo` + the 7c no-reader recipe | ✅ |

End state: a fresh user adds the lazy spec, sets `holdir` only if their HOL
is not discoverable, and everything works --- no dotfiles, no exported
environment variables, nothing copied by hand.

-   [x] **7a --- auto-bootstrap Vimhol into spawned REPLs.** Right after
    `\x` spawns the terminal job, feed the pty (each line a complete
    statement --- this cannot go through `send()`: the pipe it enables is
    not up yet):

        val _ = case #lookupStruct PolyML.globalNameSpace "Vimhol" of
                  NONE => use "<holdir>/tools/editor-modes/vim/vimhol.sml"
                | SOME _ => ();
        val _ = print "hol4nvim: vimhol ready\n";

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
    continue --- the session still works, with multi-line sends and `\c`
    degrading to the raw pty exactly as they do today without the dotfile.
-   [x] **7b --- single `holdir()` resolver.** Order: `config.holdir` →
    derived from the resolved hol binary (`.../bin/hol`, resolved through
    `$PATH` and symlinks, two dirs up, accepted when a `tools/` sibling
    confirms a HOL tree --- covers lastmaker and `hol_cmd` too) → `$HOLDIR`
    demoted to last-resort fallback. `holdeptool()` and `fifo.path()`'s
    default now route through it (7a discovery will too). One
    `holdir = "..."` line in the lazy spec (or nothing at all when hol is
    discoverable) configures everything; the README setup section no longer
    asks for environment variables.
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
    every pipe-routed multi-line send, `\c` interrupt, and `\l` in the
    suite runs on the plugin's own bootstrap with zero dotfiles. The
    guard's other branch --- a config that pre-loads Vimhol: bootstrap
    no-ops, the sentinel still prints, and a pipe-routed probe evaluates
    exactly once --- is verified by a standalone smoke script; folding that
    into the suite costs a second hol boot, deferred to Phase 6 polish
    alongside `:checkhealth hol4nvim` naming the exact missing `setup()`
    option whenever a discovery step fails.

Phase 7 complete ✅

## Keep in view (not primary)

-   [ ] Search window: a toggleable split/float querying the live session
    over loaded theories --- pattern search (`DB.apropos` /
    `Hol_pp.print_apropos` on a term) and name search (`DB.find` /
    `Hol_pp.print_find`), with results rendered in the window rather than
    scrolling the REPL.

## Upstream mapping reference (`<LocalLeader>` = `h` by default)

    x new REPL      X close REPL     w/s send         u send quiet
    e expand        g goal           G unquoted goal  S subgoal
    F suffices      P pattern        l load deps
    R rotate        b backup         B restore        v save
    d drop          p p()            r restart        c interrupt
    t sel `term`    T sel ``term``   a sel Theorem    y show_types
    n avoid_unicode h h (passthru)
