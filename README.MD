# hol4nvim

A port of the default vim configuration shipped with [HOL4](https://hol-theorem-prover.org/)
(`tools/editor-modes/vim/`) to Neovim, for users of [lazy.nvim](https://github.com/folke/lazy.nvim).

See [ROADMAP.md](ROADMAP.md) for parity status with the upstream vim config.

## Install (lazy.nvim)

```lua
{
  "artisanbk/hol4nvim",
  ft = "hol4script", -- lazy-load on HOL4 script files; see "Filetype detection"
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
                              -- \x (skipped if your hol-config already does;
                              -- false disables, or give an explicit path)
      keymaps = true,         -- false disables all buffer-local keymaps
      prefix = "<localleader>", -- keymap prefix
      abbreviations = false,  -- holabs ASCII->unicode insert abbreviations
    })
  end,
}
```

Path options (`hol_cmd`, `holdir`, `fifo`, a string `vimhol`) may use `~`;
it is expanded by `setup()`.

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

REPLs started by `\x` get Vimhol loaded automatically — no `~/.hol-config.sml`
needed. The bootstrap is a guarded `use`: if your hol-config (or `$HOL_CONFIG`)
already loads Vimhol it does nothing, and it announces itself with a
`hol4nvim: vimhol ready` line once the session can take fifo-routed sends.

## Keymaps

Buffer-local on `hol4script` buffers (`*Script.sml`). `<localleader>` defaults
to `\`. Send-style maps work on the current line (normal mode) or the
selection (visual mode); SML `(* ... *)` comments are stripped from the text
before sending, and comment-only selections are not sent.

| Map | Action |
|-----|--------|
| `\x` | Start a HOL REPL in a split |
| `\X` | Close the current REPL (sends Ctrl-D) |
| `\s` (`\w` alias) | Send raw SML |
| `\u` | Send quietly (wrapped in `quietdec` toggles — no result printout) |
| `\!` | Send the whole document; `open` declarations are dropped (use `\l` for those) |
| `\e` | Apply as a tactic to the current goal (`proofManagerLib.expand`) |
| `\g` | Set as the goal — include the backquotes (`proofManagerLib.g`) |
| `\G` | Set an unquoted goal from Theorem-statement + `Proof` lines; handles `Proof[attrs]` and `Resume thm[label]:` headers |
| `\S` | Prove as a subgoal; a trailing `` by ...`` is stripped (`bossLib.sg`) |
| `\F` | Suffices-to-show; a trailing `suffices_by ...` is stripped (`bossLib.qsuff_tac`) |
| `\P` | Apply to pattern-selected subgoals (`Q.SELECT_GOAL_LT`) |
| `\l` | Run holdeptool over the text, `load` each dependency, execute the text quietly, print `HOLLoad ... completed` |
| `\b` / `\B` | Back up a proof step / restore save point (a count repeats: `3\b`) |
| `\v` / `\d` | Save proof state / drop current goal (count repeats `\d`) |
| `\p` / `\r` | Print current proof state / restart the goal |
| `\R` | Rotate subgoals (count = how far) |
| `\c` | Interrupt the running tactic (via the Vimhol fifo, else Ctrl-C) |
| `\t` / `\T` | Select the enclosing `` `term` `` / ``` ``term`` ``` |
| `\a` | Select the theorem statement + `Proof` lines (feed it to `\G`) |
| `\y` / `\n` | Toggle `show_types` / unicode pretty-printing |
| `\h` | Pass-through `h` (so `hh` moves left when `<localleader>` is `h`) |

Commands: `:HolStart`, `:HolStop`, `:HolSend` (range-aware), `:HolSendDocument`,
`:HolUnabbrev` (unicode → ASCII, whole buffer or range).

With `abbreviations = true`, insert mode gets the
[holabs](https://github.com/HOL-Theorem-Prover/HOL/blob/master/tools/editor-modes/vim/holabs.vim)
ASCII→unicode abbreviations: type `/\` `\/` `==>` `<=>` `!` `?` `IN` `SUBSET` ...
followed by a space to get `∧ ∨ ⇒ ⇔ ∀ ∃ ∈ ⊆`.

## Syntax highlighting

`syntax/hol4script.vim` — a verbatim port of upstream's regex highlighting —
loads automatically for `*Script.sml`. A tree-sitter tier is roadmapped
(ROADMAP Phase 5b/5c: a self-contained `holscript` grammar built by a lazy
`build` hook, no nvim-treesitter dependency); once its parser is built it
takes precedence per buffer and the regex file remains the zero-requirements
fallback.

### Known limitations of the regex tier

All inherited from upstream — vim renders these identically. They are what
the tree-sitter tier is designed to fix.

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
`examples/WholeScript.sml` is a linear script demonstrating `\!`
(send whole document).
