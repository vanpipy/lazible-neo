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

## Help LazyVim
* Enable fzf plugin manually, then,
* `sudo apt install luarocks fzf`
```
