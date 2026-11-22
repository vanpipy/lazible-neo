# 💤 Lazible Neo

Follow the [LazyVim](https://github.com/LazyVim/LazyVim) and [lazy.nvim](https://github.com/folke/lazy.nvim).

## Features

### Academic Writing

- LaTeX: `lervag/vimtex`
  - `latexmk` compiler
  - folds + syntax + completion enabled
  - viewer: `general` on Windows, otherwise `zathura` if available
- Markdown:
  - `MeanderingProgrammer/render-markdown.nvim`
  - `dkarter/bullets.vim`
- Writing-friendly ftplugin defaults for `tex` and `markdown`:
  - `spell`, `wrap`, `linebreak`, `conceallevel=2`, `textwidth=100`

### UI / Navigation

- Theme: `folke/tokyonight.nvim` (colorscheme: `tokyonight`)
- `snacks.nvim`:
  - dashboard enabled
  - picker: show hidden files, `<a-c>` toggle cwd/root
- Telescope disabled (Snacks picker is the primary picker)

### Editing

- `kylechui/nvim-surround`

### Keymaps

- Diagnostics / Navigation:
  - `K` line diagnostics
  - `ga` go to beginning of line
  - `gl` go to end of line

- Gitsigns (leader is `;`):
  - `;hs` stage hunk
  - `;hr` reset hunk
  - `;hS` stage buffer
  - `;hR` reset buffer
  - `;hp` preview hunk
  - `;hi` preview hunk inline
  - `;hb` blame line
  - `;hB` toggle the inline blame annotation
  - `;hd` diff this
  - `;hD` diff this `~`
  - `;hQ` hunks of all repositories (quickfix list)
  - `;hq` hunks of the current buffer (quickfix list)
  - `;hs` and `;hr` also work in Visual mode, and stage or reset the selected range

  LazyVim's own `<leader>gh*` shortcuts are still available alongside these.
  The `<leader>h*` ones are global, so they work in any buffer, while the
  `<leader>gh*` ones only exist in git-backed buffers.

- Current line author:
  - The author of the line under the cursor is shown inline, at the end of the
    line, with no keypress at all. It updates as you move the cursor.
  - `;hb` opens the full blame popup (commit, summary, file) for that line.
  - `;hB` switches the inline annotation off and on again.

```bash
git clone https://github.com/vanpipy/lazible-neo.git ~/.config/nvim
```

## Help LazyVim (Subsystem / Kali / Debian)

Some plugins rely on external binaries. On WSL/Kali/Debian-based systems, install:

```bash
sudo apt update
sudo apt install -y \
  ripgrep fd-find \
  build-essential \
  luarocks \
  ghostscript \
  texlive-base texlive-binaries texlive-bibtex-extra biber latexmk \
  zathura zathura-pdf-poppler \
  lazygit
```

What these are for:

- `ripgrep` / `fd-find`: required by Snacks picker for grep/file search
- `build-essential`: Tree-sitter parsers and native plugins compilation
- `luarocks`: LuaRocks for some Lua tooling/plugins that rely on external Lua modules
- `ghostscript`: PDF utility used by parts of LaTeX/PDF toolchains
- `texlive-base` / `texlive-binaries`: minimal LaTeX distribution and binaries
- `texlive-bibtex-extra` / `biber`: bibliography toolchain (BibTeX styles + biblatex backend)
- `latexmk`: VimTeX default compiler wrapper (recommended with `vimtex_compiler_method=latexmk`)
- `zathura` / `zathura-pdf-poppler`: optional PDF viewer and backend for VimTeX on Linux
- `lazygit`: optional TUI git client used by LazyVim git workflows

Notes:

- On Debian/Ubuntu, `fd-find` installs the `fdfind` binary. If `fd` is missing, create a symlink so pickers can use it:

```bash
sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd
```

Language extras (optional):

- TypeScript / JavaScript: install `nodejs` + `npm` (Mason tools like tsserver/eslint/prettier need Node)
- Python: install `python3` + `python3-venv`
- Go: install `golang` (the `gopls` language server needs a Go toolchain)

Optional (clipboard integration inside subsystem):

```bash
sudo apt install -y xclip wl-clipboard
```
