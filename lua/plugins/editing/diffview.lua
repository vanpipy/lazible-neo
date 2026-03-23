return {
  "sindrets/diffview.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewLog" },
  keys = {
    { "<leader>gV", "<cmd>DiffviewOpen<cr>", desc = "Diffview Open" },
    { "<leader>gX", "<cmd>DiffviewClose<cr>", desc = "Diffview Close" },
    { "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview File History" },
    { "<leader>gF", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview History" },
  },
}
