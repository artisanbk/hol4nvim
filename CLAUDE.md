# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A port of the default Vim configuration shipped with [HOL4](https://hol-theorem-prover.org/) (the HOL4 interactive theorem prover) to Neovim, targeting users of [lazy.nvim](https://github.com/folke/lazy.nvim) for plugin management.

The repository is in an early/stub stage: the files currently sketch the intended structure rather than provide a working configuration. Expect incomplete and placeholder code (e.g. unfinished statements, typos). When editing, treat the existing lines as intent to be completed, not as a working baseline to preserve.

## Structure

- `init.lua` — Neovim entry point. Bootstraps lazy.nvim and declares the plugin spec via `require("lazy").setup({ ... })`.
- `ftplugin/hol.lua` — Buffer-local setup that loads only for buffers with the `hol` filetype (Neovim runs `ftplugin/<filetype>.lua` automatically on `FileType`). HOL4-specific buffer options, keymaps, and commands belong here. Uses the standard `vim.b.did_ftplugin` reload guard.

## Conventions

- Configuration is Lua, using the `vim.*` Neovim API (e.g. `vim.b`, `vim.opt`, `vim.api`), not Vimscript.
- Filetype-specific behavior goes in `ftplugin/`, not in `init.lua`. `init.lua` is for global setup and the plugin spec.

## Reference

The behavior being ported is HOL4's `tools/vim/` configuration in the HOL4 source tree. Consult it when deciding which mappings, commands, and options the Neovim port should reproduce.
