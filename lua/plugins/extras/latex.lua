return {
  {
    "lervag/vimtex",
    ft = { "tex" },
    init = function()
      vim.g.vimtex_compiler_method = "latexmk"
      vim.g.vimtex_fold_enabled = 1
      vim.g.vimtex_quickfix_mode = 0
      vim.g.vimtex_syntax_enabled = 1
      vim.g.vimtex_complete_enabled = 1

      if vim.fn.has("win32") == 1 then
        vim.g.vimtex_view_method = "general"
      else
        vim.g.vimtex_view_method = vim.fn.executable("zathura") == 1 and "zathura" or "general"
      end
    end,
  },
}
