# holnvim roadmap

Goal: **full parity** with HOL4's upstream `tools/editor-modes/vim/` config, as a
native Neovim/Lua plugin for lazy.nvim users. "Done" means a HOL4 user switching
from the upstream vim setup loses no mapping, command, or syntax behaviour.

Upstream reference (HOL4 source tree):

- `hol.vim` — REPL management + all proof transforms and proof-manager commands
- `holabs.vim` — Unicode input abbreviations + reverse (`HOLUnab`)
- `hol4script.vim` — syntax highlighting (HOL terms vs ML)
- `filetype.vim` — `*Script.sml` detection

## Architecture (keep this shape)

- `transform.lua` — the **what to send** layer: pure `string -> string` reshapers
  (expand, goal, subgoal, ...). No plugin dependencies; never in a require cycle.
- `repl.lua` — the **how to send** layer: terminal vs fifo transport, `auto`
  routing, session stack, HOL discovery. Holds `M.config`.
- `fifo.lua` — fifo transport for an external HOL session (Vimhol `ReadFile`).
- `init.lua` (module) — public `setup(opts)` + user commands.
- `ftplugin/hol4script.lua` — buffer-local keymaps/options.
- `ftdetect/hol4script.lua` — filetype detection.

This is already an improvement over upstream, which hard-splits the terminal path
(`\w`) from the fifo path (`\s` and the `HOLCall` C-channel). Here a single
`send()` picks the transport, so every transform and command routes through it.

## Status legend

✅ done · 🟡 partial · ⬜ not started

## Current state

| Capability | Upstream | holnvim | Status |
|---|---|---|---|
| Filetype detection | `filetype.vim` | `ftdetect/hol4script.lua` | ✅ |
| REPL open / close | `\x` / `\X` | `repl.open` / `repl.close` | ✅ |
| HOL discovery (lastmaker/$HOLDIR) | `WhichHOL` | `which_hol` | ✅ |
| Session stack + prune on exit | `g:hol_repl` | `M.sessions` | ✅ |
| Dual transport (terminal + fifo) | split mappings | `transport="auto"` | ✅ (better) |
| Send raw line / selection | `\s` `\w` | `\s` | ✅ |
| Expand tactic | `\e` | `\e` | 🟡 no token-stripping |
| Load deps | `\l` | `\l` | 🟡 no quietdec wrap / "completed" print |

## Phases

### Phase 0 — Foundation & cleanup
- [ ] Decide `lua/holnvim/keymaps.lua`: make it the single keymap registry (move
      inline maps out of `ftplugin/hol4script.lua`) **or** delete it. Currently empty.
- [ ] Reconcile the keymap scheme with upstream's letters so muscle memory carries
      over (document any intentional divergence). Reserve the upstream letters
      below for their upstream meaning.
- [ ] Settle the `config` surface (keymaps on/off, prefix, transport, split,
      hol_cmd, fifo) and document defaults.

### Phase 1 — Proof transforms (highest daily value)
Pure additions to `transform.lua`, each wired to a keymap + routed through `send()`.
- [ ] `\g` goal — `proofManagerLib.g(...)` (handle trailing-comma / multi-goal form)
- [ ] `\S` subgoal — `proofManagerLib.expand(bossLib.sg(...))`, strip trailing `by ...`
- [ ] `\F` suffices — `proofManagerLib.expand(bossLib.qsuff_tac(...))`, strip `suffices_by ...`
- [ ] `\P` pattern — `proofManagerLib.expand_list(Q.SELECT_GOAL_LT(...))`
- [ ] `\G` unquoted goal — Theorem-block + `Resume <thm>[<label>]:` handling via
      `markerLib.set_suspended_goal` / `proofManagerLib.new_goalstack`. **Hairiest;
      do last.**

### Phase 2 — Proof-manager control commands
Thin `repl.lua` wrappers sending literal `proofManagerLib.*` strings via `send()`.
- [ ] `\b` backup · `\B` restore · `\v` save · `\d` drop · `\p` p() · `\r` restart
- [ ] `\R` rotate — honour a count (`v:count1`)
- [ ] `\c` Interrupt — upstream sends `Interrupt` over the fifo C-channel

### Phase 3 — Send refinements
- [ ] `\u` quiet send — wrap in `HOL_Interactive.toggle_quietdec()` toggles
- [ ] Expand token-stripping — strip leading/trailing `THEN`/`>>`/`by`/brackets so
      sloppy selections still parse (port `s:strip*` regex logic)
- [ ] Full `\l` load parity — quietdec wrap + "...completed" print (or document the
      simplification as intentional)

### Phase 4 — Editing ergonomics
- [ ] Unicode abbreviations from `holabs.vim` (`/\→∧`, `==>→⇒`, `!→∀`, ...) in the ftplugin
- [ ] `:HolUnabbrev` command — reverse Unicode → ASCII (port `HOLUnab`)
- [ ] Selection-movement helpers: `\t` single-quote term, `\T` double-quote term,
      `\a` Theorem…Proof block (motions, no send)
- [ ] Toggles: `\y` `Globals.show_types`, `\n` `PP.avoid_unicode`

### Phase 5 — Syntax highlighting
- [ ] Ship `syntax/hol4script.vim` (port upstream verbatim — lowest risk).
      A Treesitter/Lua route is a separate, larger effort, not parity.

### Phase 6 — Polish & release
- [ ] `:checkhealth holnvim` (hol/holdeptool/HOLDIR/fifo, transport sanity)
- [ ] README + `:help holnvim` doc; mapping table
- [ ] Tests (transform layer is pure → easy to unit test)
- [ ] Tag a release; finalise the published lazy.nvim spec snippet

## Upstream mapping reference (`<LocalLeader>` = `\` by default)

```
x new REPL      X close REPL     w/s send         u send quiet
e expand        g goal           G unquoted goal  S subgoal
F suffices      P pattern        l load deps
R rotate        b backup         B restore        v save
d drop          p p()            r restart        c interrupt
t sel `term`    T sel ``term``   a sel Theorem    y show_types
n avoid_unicode h h (passthru)
```
