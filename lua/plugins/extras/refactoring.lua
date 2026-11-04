-- Refactoring.nvim
--
-- Self-contained replacement for the LazyVim `editor.refactoring` extra.
-- The extra is NOT enabled in lazyvim.json because it targets the pre-649a53c
-- API. Upstream commit 649a53c ("refactor!: new user facing interface for
-- refactors") removed the public `refactor(name)` entry point, the
-- `get_refactors()` helper, and the module-level `debug` table. Every keymap
-- in the stale extra calls one of those, so it raises
-- "attempt to call a nil value". The extra also lists a Telescope extension
-- that no longer exists, and it pulls in plenary.nvim for no reason.
--
-- This spec uses only the current public API, verified against the installed
-- plugin at ~/.local/share/nvim/lazy/refactoring.nvim:
--   require("refactoring").extract_func()
--   require("refactoring").extract_func_to_file()
--   require("refactoring").extract_var()
--   require("refactoring").inline_var()
--   require("refactoring").inline_func()
--   require("refactoring").select_refactor()
--   require("refactoring").setup(opts)
-- Debug helpers live in a separate module:
--   require("refactoring.debug").print_var()
--   require("refactoring.debug").print_loc()
--   require("refactoring.debug").print_exp()
--   require("refactoring.debug").cleanup()
--
-- Dependencies:
--   async.nvim is required directly by refactoring.nvim (lua/refactoring.lua
--   and several refactor/*.lua modules call `require "async"`), so it is
--   declared explicitly rather than relied on transitively.
--   nvim-treesitter is not declared here. LazyVim already provides it, and
--   refactoring.nvim ships its own `queries/` tree for the refactor_* captures.
--   It does not use plenary.nvim.
--
-- Text objects:
--   The refactor entry points return the keys to feed to `g@` / `g@l`, so they
--   must be bound with expr = true.
--   `<leader>rv` and `<leader>rf` use the built-in `iw`/`_` style selections
--   via the operator, so they run in visual mode over a selection.
--   `<leader>rc` (debug cleanup) needs a range, and mini.ai's `ag` selects the
--   whole buffer. LazyVim wires `g` to `LazyVim.mini.ai_buffer` in
--   lua/lazyvim/plugins/coding.lua, so `ag` is available in operator-pending
--   mode.
--
-- Keymaps:
--   <leader>rs  Select Refactor        (vim.ui.select picker)
--   <leader>ri  Inline Variable
--   <leader>rI  Inline Function
--   <leader>rv  Extract Variable
--   <leader>rf  Extract Function
--   <leader>rF  Extract Function To File
--   <leader>rP  Debug Print Location
--   <leader>rp  Debug Print Variable
--   <leader>rc  Debug Print Cleanup
return {
  "ThePrimeagen/refactoring.nvim",
  dependencies = {
    "lewis6991/async.nvim",
  },
  event = { "BufReadPre", "BufNewFile" },
  keys = {
    { "<leader>r", "", desc = "+refactor", mode = { "n", "x" } },

    {
      "<leader>rs",
      function()
        require("refactoring").select_refactor()
      end,
      mode = { "n", "x" },
      desc = "Select Refactor",
    },
    {
      "<leader>ri",
      function()
        return require("refactoring").inline_var()
      end,
      mode = { "n", "x" },
      desc = "Inline Variable",
      expr = true,
    },
    {
      "<leader>rI",
      function()
        return require("refactoring").inline_func()
      end,
      mode = { "n", "x" },
      desc = "Inline Function",
      expr = true,
    },
    {
      "<leader>rv",
      function()
        return require("refactoring").extract_var()
      end,
      mode = { "n", "x" },
      desc = "Extract Variable",
      expr = true,
    },
    {
      "<leader>rf",
      function()
        return require("refactoring").extract_func()
      end,
      mode = { "n", "x" },
      desc = "Extract Function",
      expr = true,
    },
    {
      "<leader>rF",
      function()
        return require("refactoring").extract_func_to_file()
      end,
      mode = { "n", "x" },
      desc = "Extract Function To File",
      expr = true,
    },
    {
      "<leader>rP",
      function()
        return require("refactoring.debug").print_loc({ output_location = "below" })
      end,
      mode = { "n" },
      desc = "Debug Print Location",
      expr = true,
    },
    {
      "<leader>rp",
      function()
        return require("refactoring.debug").print_var({ output_location = "below" })
      end,
      mode = { "x" },
      desc = "Debug Print Variable",
      expr = true,
    },
    {
      "<leader>rc",
      function()
        return require("refactoring.debug").cleanup({ restore_view = true }) .. "ag"
      end,
      mode = { "n" },
      desc = "Debug Print Cleanup",
      expr = true,
      -- Required. Without `remap`, the keys returned by an `expr` mapping are
      -- executed with remapping disabled, so the trailing `a` never resolves to
      -- mini.ai's operator-pending "around" mapping. Vim then treats `a` as the
      -- built-in argument-textobject prefix and `g` as an invalid argument
      -- character, cancels the operator, and the cleanup never runs.
      remap = true,
    },
  },
}
