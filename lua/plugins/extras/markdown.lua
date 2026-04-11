return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    enabled = false,
    opts = {
      file_types = { "markdown" },
    },
  },
  {
    "dkarter/bullets.vim",
    ft = { "markdown", "text", "gitcommit" },
    init = function()
      vim.g.bullets_enabled_file_types = { "markdown", "text", "gitcommit" }
    end,
  },
}
