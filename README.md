# 💤 Lazible Neo

Follow the [LazyVim](https://github.com/LazyVim/LazyVim) and [lazy.nvim](https://github.com/folke/lazy.nvim).

## Features

### AI (opencode.nvim)

- Deep integration with `nickjvandyke/opencode.nvim` + `folke/snacks.nvim` terminal
- Default server port: `4189` (config: [opencode.json](./opencode.json))
- Keymaps:
  - `<leader>oo` toggle opencode terminal
  - `<leader>oa` ask (normal/visual)
  - `<leader>op` prompt
  - `<leader>os` select
  - `<leader>oC` open `/connect`
  - `<leader>oM` open `/models`
  - `<leader>oD` restart with DeepSeek model
  - `<leader>o0` restart with default model
  - `<leader>oh` `:checkhealth opencode`
- Env vars:
  - `DEEPSEEK_API_KEY` (used by [opencode.json](./opencode.json))
  - `OPENCODE_PORT` (override default port)
  - `OPENCODE_MODEL_DEEPSEEK` / `OPENCODE_MODEL_DEFAULT` (override model switch behavior)

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
- Java: install `openjdk-17-jdk` (jdtls requires a JDK)

Optional (clipboard integration inside subsystem):

```bash
sudo apt install -y xclip wl-clipboard
```
