-- Markdown rendering is disabled deliberately (see commit 676ff7c): the
-- render-markdown.nvim plugin competes with the native markdown renderer and
-- the repo relies on the plain buffer view plus `after/ftplugin/markdown.lua`
-- for wrapping/spell settings.
--
-- The spec is kept (rather than deleted) so the plugin stays pinned in
-- lazy-lock.json and can be re-enabled by flipping `enabled` to true.
return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    enabled = false,
  },
  {
    "dkarter/bullets.vim",
    ft = { "markdown", "text", "gitcommit" },
    init = function()
      vim.g.bullets_enabled_file_types = { "markdown", "text", "gitcommit" }
    end,
  },
}
