# hol4nvim

[![CI](https://github.com/artisanbk/hol4nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/artisanbk/hol4nvim/actions/workflows/ci.yml)

A port of the default vim configuration shipped with [HOL4](https://hol-theorem-prover.org/)
(`tools/editor-modes/vim/`) to Neovim, for users of [lazy.nvim](https://github.com/folke/lazy.nvim).

See [ROADMAP.md](ROADMAP.md) for parity status with the upstream vim config.

## Install (lazy.nvim)

```lua
{
  "artisanbk/hol4nvim",
  version = "*", -- install the latest stable tag (omit to track master)
  ft = "hol4script", -- lazy-load on HOL4 script files; see "Filetype detection"
  build = "make parsers", -- compile the tree-sitter syntax tier (needs cc;
                          -- optional: without it the regex tier loads instead)
  dependencies = { "hrsh7th/nvim-cmp" }, -- optional: powers insert-mode
                                         -- completion (see "Completion")
  config = function()
    require("hol4nvim").setup({
      -- defaults shown; all optional
      hol_cmd = nil,          -- explicit hol binary (a directory works too:
                              -- bin/ or the HOL root); else .HOLMK/lastmaker,
                              -- then <holdir>/bin/hol, then $HOLDIR/bin/hol,
                              -- then hol on $PATH
      holdir = nil,           -- HOL installation root; else derived from the
                              -- hol binary being run, else $HOLDIR. Used for
                              -- holdeptool (\l) and the default fifo path
      split = "vertical",     -- REPL window: "vertical" | "horizontal"
      start_insert = false,   -- focus the REPL in insert mode after \x
      transport = "auto",     -- "auto" | "terminal" | "fifo"
      fifo = nil,             -- fifo path; else $VIMHOL_FIFO, else
                              -- <holdir>/tools/editor-modes/vim/fifo
      vimhol = true,          -- auto-load vimhol.sml into REPLs started by
                              -- hx (skipped if your hol-config already does;
                              -- false disables, or give an explicit path)
      keymaps = true,         -- false disables all buffer-local keymaps
      prefix = "<localleader>", -- keymap prefix
      abbreviations = false,  -- holabs ASCII->unicode insert abbreviations
      shell_rc = nil,         -- rc file :HolExternalSetup writes to; else
                              -- derived from $SHELL (or pass a path to it)
      auto_shell_rc = false,  -- true keeps that block current on setup(),
                              -- so external hol works without the command
      completion = {          -- insert-mode completion (needs nvim-cmp)
        enabled = true,       -- master switch (:HolCompletionToggle at runtime)
        auto_setup = true,    -- register + add the source to hol4script's cmp
        tactics = true,       -- offer the static HOL tactic vocabulary
        theorems = true,      -- offer live theorem names from the session DB
      },
    })
  end,
}
```

Path options (`hol_cmd`, `holdir`, `fifo`, `shell_rc`, a string `vimhol`)
may use `~`; it is expanded by `setup()`.

In practice the whole config is `holdir` — the hol binary, holdeptool,
the fifo, and vimhol.sml all derive from it — and even `holdir` only when
`hol` is not already discoverable ($PATH, lastmaker, $HOLDIR). A complete
copy-paste-able init is in
[examples/user-init.lua](examples/user-init.lua).

### Filetype detection

The plugin ships its own detection (`ftdetect/hol4script.lua`): a
`vim.filetype.add` pattern maps `*Script.sml` to the `hol4script` filetype.
Pattern matches take precedence over extension matches, so HOL script files
win over Neovim's built-in `*.sml` → `sml` detection while ordinary SML
files are left alone.

With `ft = "hol4script"` in the spec (recommended), lazy.nvim sources the
plugin's `ftdetect/` files eagerly at startup but loads the plugin itself —
`setup()`, keymaps, syntax — only when the first HOL4 script buffer opens.
Opening `FooScript.sml` is what launches the plugin; other files never pay
for it. Omitting `ft` simply loads everything at startup instead; detection
behaves identically either way. Nothing needs to be configured for this —
no autocmds, no manual `:set filetype`.

`transport = "auto"` sends to the in-vim `:terminal` REPL if one is open,
otherwise to an external HOL session tailing the Vimhol fifo. If no reader
is attached, the warning names the fifo and the exact recipe to start one
(`VIMHOL_FIFO='<path>' hol` plus a guarded `use` of vimhol.sml to paste into
it) — and creates the fifo, so the pasted command finds a working pipe.

REPLs started by `hx` get Vimhol loaded automatically — no `~/.hol-config.sml`
needed. The bootstrap is a guarded `use`: if your hol-config (or `$HOL_CONFIG`)
already loads Vimhol it does nothing, and it announces itself with a
`hol4nvim: vimhol ready` line once the session can take fifo-routed sends.

### External sessions out of the box (`:HolExternalSetup`)

To drive a `hol` you start yourself in a terminal (not the in-vim `hx` REPL),
that session has to load Vimhol so it tails the fifo. Run `:HolExternalSetup`
once: it writes a small, machine-agnostic loader to Neovim's data dir
(`stdpath("data")/hol4nvim/hol-config.sml`) and appends a managed block to your
shell rc that points `$HOL_CONFIG` at it:

```sh
# >>> hol4nvim (managed) >>>
export HOL_CONFIG='…/hol4nvim/hol-config.sml'
export VIMHOL_FIFO='…/tools/editor-modes/vim/fifo'
# <<< hol4nvim (managed) <<<
```

The rc is chosen from `$SHELL` (`~/.zshrc`, `~/.bashrc`, or fish's
`config.fish`, which gets `set -gx` instead of `export`); override it with
`config.shell_rc = "~/.myrc"` or a one-off `:HolExternalSetup ~/.myrc`. The
block is written **only** when you run the command — never on plugin load —
between markers, so re-running updates it in place and deleting the block
removes it cleanly. Start (or restart) hol, or `source` the file, and it takes
effect.

Set `auto_shell_rc = true` to skip the command: `setup()` then writes and
updates that same block itself, so the plugin is configured for external
sessions as soon as it loads. It stays off by default because writing to a
shell rc should be something you asked for — the flag *is* that request, made
once in your config instead of once per command. The write is idempotent, so
running it on every load is a no-op once the block is correct, and it follows
your HOL if the paths ever change. What it cannot do is affect shells that are
already open: the first time, you still need a new terminal and a new `hol`.

After that, every `hol` you start attaches Vimhol and `hl`/`hs`/… reach it —
no per-session paste. **No `~/.hol-config.sml` is created**: the loader lives
in the data dir, and because `$HOL_CONFIG` *replaces* HOL's own config search,
it runs your own hol-config first (if any) and then attaches Vimhol, guarded so
a preloading config is never re-tailed. The loader resolves `vimhol.sml` from
`$HOLDIR` at runtime (falling back to the path resolved when it was written),
so it is not tied to the machine that generated it. The plugin regenerates the
loader on every `setup()`, so it stays current.

## Keymaps

Buffer-local on `hol4script` buffers (`*Script.sml`). The prefix is
`<localleader>`; following HOL's convention these examples set it to `h`
(`vim.g.maplocalleader = "h"`), so the maps read `hx`, `hs`, `he`, …. Send-style
maps work on the current line (normal mode) or the selection (visual mode); SML
`(* ... *)` comments are stripped from the text before sending, and comment-only
selections are not sent.

| Map | Action |
|-----|--------|
| `hx` | Start a HOL REPL in a split |
| `hX` | Close the current REPL (sends Ctrl-D) |
| `hs` (`hw` alias) | Send raw SML |
| `hu` | Send quietly (wrapped in `quietdec` toggles — no result printout) |
| `h!` | Send the whole document; `open` declarations and new-style `Theory`/`Ancestors`/`Libs` headers are dropped (use `hl` for those) |
| `he` | Apply as a tactic to the current goal (`proofManagerLib.expand`) |
| `hg` | Set as the goal — include the backquotes (`proofManagerLib.g`) |
| `hG` | Set an unquoted goal from Theorem-statement + `Proof` lines; handles `Proof[attrs]` and `Resume thm[label]:` headers |
| `hS` | Prove as a subgoal; a trailing `` by ...`` is stripped (`bossLib.sg`) |
| `hF` | Suffices-to-show; a trailing `suffices_by ...` is stripped (`bossLib.qsuff_tac`) |
| `hP` | Apply to pattern-selected subgoals (`Q.SELECT_GOAL_LT`) |
| `hl` | Run holdeptool over the text, `load` each dependency, execute the text quietly, print `HOLLoad ... completed` |
| `hb` / `hB` | Back up a proof step / restore save point (a count repeats: `3hb`) |
| `hv` / `hd` | Save proof state / drop current goal (count repeats `hd`) |
| `hp` / `hr` | Print current proof state / restart the goal |
| `hR` | Rotate subgoals (count = how far) |
| `hc` | Interrupt the running tactic (via the Vimhol fifo, else Ctrl-C) |
| `ht` / `hT` | Select the enclosing `` `term` `` / ``` ``term`` ``` |
| `ha` | Select the theorem statement + `Proof` lines (feed it to `hG`) |
| `hf` | Open a search panel: theorems by name (`DB.find`) — see Search |
| `hm` | Open a search panel: theorems by term (`DB.apropos`); visual mode seeds the selection |
| `hy` / `hn` | Toggle `show_types` / unicode pretty-printing |
| `hh` | Pass-through `h` (so `hh` moves left when `<localleader>` is `h`) |

Commands: `:HolStart`, `:HolStop`, `:HolSend` (range-aware), `:HolSendDocument`,
`:HolUnabbrev` (unicode → ASCII, whole buffer or range), `:HolFind [name]`,
`:HolMatch [term]`, `:HolExternalSetup` (external-session loader; see above),
`:HolCompletionRefresh`, `:HolCompletionToggle`.

Full docs live in `:help hol4nvim`. If anything misbehaves, run
`:checkhealth hol4nvim`: it reports the resolved hol binary, HOL root,
holdeptool, vimhol.sml, fifo, and tree-sitter parsers — naming the exact
`setup()` option to set on any failure — and flags a keymap `prefix` that
collides with your leader (a common source of input lag; see below).

With `abbreviations = true`, insert mode gets the
[holabs](https://github.com/HOL-Theorem-Prover/HOL/blob/master/tools/editor-modes/vim/holabs.vim)
ASCII→unicode abbreviations: type `/\` `\/` `==>` `<=>` `!` `?` `IN` `SUBSET` ...
followed by a space to get `∧ ∨ ⇒ ⇔ ∀ ∃ ∈ ⊆`.

## Search

`hf` / `:HolFind` and `hm` / `:HolMatch` open a search **panel** — a horizontal
split of the current window whose top line names the search type, with an
editable query bar below it. Type a query and press `<CR>` to run it; the
results fill the panel, and editing the bar and pressing `<CR>` again re-runs.
Press `<CR>` on a result line to insert that theorem's name at the cursor in
the window you searched from (it's yanked to the unnamed register too). `q`
closes the panel. `hf` searches theorem names (`DB.find`); `hm` searches by
term pattern (`DB.apropos`), and in visual mode seeds the bar with the
selection. The bar starts pre-filled with the word under the cursor.
`:HolFind name` / `:HolMatch term` run a search straight away.

The plugin's transport is one-way — it can send to HOL but not read answers
back — so a search is SML that writes its formatted results to a temp file,
which Neovim polls and renders, pretty-printed and highlighted with the
`holterm` grammar. A search needs a running session (start one with `hx`); a
bad term pattern reports the error instead of hanging.

## Completion

Insert-mode completion in `hol4script` buffers, exposed as an
[nvim-cmp](https://github.com/hrsh7th/nvim-cmp) source. Two vocabularies:

- **HOL tactics/tacticals** — a curated static list (`rw`, `simp`, the `drule`
  family, `qexists_tac`, `Induct_on`, the tacticals, …). No REPL needed.
- **Theorem names** — snapshotted from the running session's `DB.listDB()`
  (public theorems only), so completion tracks whatever theories are loaded.

The source is registered and, with `auto_setup = true`, added to the
`hol4script` filetype's cmp sources automatically — with nvim-cmp installed it
just works; the popup appears as you type. Accepting a theorem completion
inserts the bare name (e.g. `ADD_ASSOC`), matching how the search panel picks a
result. `:HolCompletionToggle` turns it off/on without touching your cmp config.

Because the transport is one-way, theorem names can't be queried per keystroke:
the cache is snapshotted and refreshed when a REPL starts, after `hl` loads new
dependencies, and on demand with `:HolCompletionRefresh` (an enumeration SML
writes the names to a temp file the plugin polls — the same round-trip Search
uses). Until the first refresh completes, only the tactic vocabulary shows.

Set `completion.enabled = false` (or omit nvim-cmp) to skip it entirely;
`completion.tactics` / `completion.theorems` toggle the two vocabularies.
`:checkhealth hol4nvim` reports whether nvim-cmp is present and how many
theorem names are cached.

## Syntax highlighting

Two tiers, chosen automatically per buffer:

- **tree-sitter (preferred)** — self-contained grammars ship in-repo
  (`grammar/*/`; each generated `parser.c` is vendored, so building needs
  only a C compiler). The spec's `build = "make parsers"` hook compiles them
  into `parser/*.so`, and the ftplugin uses them whenever they exist. No
  nvim-treesitter needed: Neovim core reads `parser/` and `queries/` straight
  off the plugin's runtimepath.
- **regex (fallback)** — `syntax/hol4script.vim`, a verbatim port of
  upstream's highlighting. Zero requirements; loads whenever the parser is
  not built.

The tree-sitter tier parses the script-level structure —
`Theorem/Triviality..Proof..QED`, `Definition/Termination/End`, `Datatype`,
`(Co)Inductive`, `Type`/`Overload`, new-style `Theory`/`Ancestors`/`Libs`
headers, quotations, `«»`/`""` strings, nested `(* *)` comments — and fixes
the regex tier's structural limitations:

- indented blocks highlight (regex demands column 0);
- mismatched quotation delimiters (`` `x + y’ ``) show as errors instead of
  well-formed quotations;
- edits reparse incrementally instead of `syn sync fromstart` whole-file
  rescans;
- folding covers `Definition`/`Datatype`/`Inductive..End` blocks as well as
  `Proof..QED` (folds are opt-in:
  `setlocal foldmethod=expr foldexpr=v:lua.vim.treesitter.foldexpr()`).

Block interiors are no longer flat: each is handed to a real grammar by
injection, so terms and ML highlight token-by-token (the regex tier could
only recognise a hand-curated symbol vocabulary):

- **plain ML between blocks and tactic bodies** inject the vendored
  [tree-sitter-sml](https://github.com/MatthewFluet/tree-sitter-sml)
  (`grammar/sml/`, MIT, also built by `make parsers`) — real SML keywords,
  constructors, literals;
- **unquoted term text** (`Definition`/`Datatype`/`Inductive` bodies) and
  **quotation interiors** (`` `..` ``, `` ``..`` ``, `‘..’`, `“..”`) inject
  `holterm` (`grammar/holterm/`), a small lenient grammar for the HOL term
  language — binders (`!` `?` `\` `∀` `∃` `λ`), operators, `if/then/else`,
  `T`/`F`, numbers, strings, type variables (`'a`), and `^` antiquotation.
  quotation delimiters are trimmed so only the term text is reparsed.

Each injection is best-effort: if a grammar's parser is not built, that span
simply stays opaque. `holterm` is deliberately a tokeniser, not a full parser
— HOL's concrete term syntax is user-extensible, so no fixed grammar could
parse arbitrary terms, and highlighting does not need to.

### Recolouring the theory header

The new-style header keywords are captured apart from the names they
introduce, so `Ancestors` never renders as just another imported theory:

| token | tree-sitter | regex tier |
| --- | --- | --- |
| `Theory` | `@keyword.directive` | `HOLHeaderKey` (→ `Include`) |
| `Ancestors`, `Libs` | `@keyword.import` | `HOLHeaderKey` (→ `Include`) |
| the names under them | `@module` | `HOLHeaderName` (→ `Identifier`) |

If your colorscheme renders those alike anyway (some collapse `@keyword.*`
into one colour), set them yourself — filetype-scoped, so nothing else moves:

```lua
vim.api.nvim_set_hl(0, "@keyword.import.holscript", { link = "Include" })
vim.api.nvim_set_hl(0, "@keyword.directive.holscript", { link = "Include" })
vim.api.nvim_set_hl(0, "@module.holscript", { link = "Identifier" })
```

`:Inspect` on a token reports the captures actually applied to it, which is
the quickest way to see what your scheme is doing.

### Known limitations of the regex tier

Apply only when the parser is not built. All inherited from upstream — vim
renders these identically.

- **Block keywords only count at column 0.** An indented theorem gets no
  block treatment at all:

  ```sml
    Theorem foo:      (* indented: no keyword/term/QED highlighting *)
  ```

- **Whole-file rescans** (`syn sync fromstart`): every edit re-syncs
  highlighting from the top of the file — noticeable lag in
  multi-thousand-line Script files.

- **Fixed term vocabulary.** Inside quotations only a hand-curated symbol
  list (`MAP`, `EVERY`, `LENGTH`, `SUBSET`, ...) is highlighted specially;
  everything else is a plain identifier:

  ```sml
  `SUM (GENLIST f n) + FOLDR g 0 l`   (* SUM, GENLIST, FOLDR: unhighlighted *)
  ```

- **Quote delimiters may mix.** A quotation opened with a backtick is
  happily "closed" by a unicode quote (and vice versa), so mismatches look
  well-formed instead of erroneous:

  ```sml
  `x + y’    (* highlights as a complete quotation *)
  ```

- **Simplified ML layer.** The SML side is a hand-rolled subset: `functor`,
  `abstype`, `withtype`, `sharing`, `op`, `as` are not keywords, and word /
  hex literals (`0wx1F`, `0x2A`) are not numbers.

- **No antiquotation awareness.** `^var` / `^(exp)` inside a quotation is
  ordinary term text rather than an ML splice.

- **Folding covers only `Proof`..`QED`** — `Definition`..`End` and
  `Datatype`..`End` blocks don't fold.

## Trying it / development

```sh
nvim -u init.lua examples/TestScript.sml   # isolated demo config
make test                                  # unit + end-to-end suites
make test-unit                             # the HOL-free tier only
```

`examples/TestScript.sml` is a guided tour of every implemented map — it is
made of bare fragments on purpose, so it cannot be batch-sent.
`examples/WholeScript.sml` is a linear script demonstrating `h!`
(send whole document).
