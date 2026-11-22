-- Gitsigns keymaps.
--
-- LazyVim binds its own gitsigns shortcuts under `<leader>gh*`:
--
--   <leader>ghs  stage hunk        <leader>ghp  preview hunk inline
--   <leader>ghr  reset hunk        <leader>ghb  blame line
--   <leader>ghS  stage buffer      <leader>ghd  diff this
--   <leader>ghu  undo stage hunk   <leader>ghD  diff this ~
--   <leader>ghR  reset buffer
--
-- plus `[h` / `]h` for hunk navigation.
--
-- Those LazyVim mappings are installed from gitsigns' `on_attach` callback,
-- which only runs once the plugin has attached to a buffer. They therefore
-- only exist in git-backed buffers, and they live behind a `g` that the
-- config already uses for the git picker family (`<leader>gd`, `<leader>gs`,
-- `<leader>gS` in lua/plugins/editing/snacks.lua, and the `<leader>gg*` /
-- `<leader>gf` / `<leader>gl*` / `<leader>gb` / `<leader>gB` / `<leader>gY`
-- maps in lua/config/keymaps.lua).
--
-- This file adds the shorter `<leader>h*` shortcuts on top of that, so the
-- hunk actions are reachable without the `g` infix:
--
--   <leader>hs  stage hunk            <leader>hS  stage buffer
--   <leader>hr  reset hunk            <leader>hR  reset buffer
--   <leader>hp  preview hunk          <leader>hi  preview hunk inline
--   <leader>hb  blame line (full)     <leader>hd  diff this
--   <leader>hD  diff this ~           <leader>hQ  hunks of all repos (qflist)
--   <leader>hq  hunks of this buffer  (qflist)
--
-- Two things are deliberately different from the upstream snippet this is
-- based on.
--
-- 1. The plugin is required locally instead of relying on a global
--    `gitsigns` table. Upstream gitsigns no longer creates one: the current
--    README requires the module explicitly
--    (`local gitsigns = require('gitsigns')`), and `require('gitsigns')`
--    resolves the action functions through a metatable `__index`. A global
--    reference would raise "attempt to call a nil value".
--
-- 2. The mappings are declared through lazy.nvim's `keys` field rather than
--    through `on_attach`. lazy.nvim resolves the right-hand side lazily and
--    loads the plugin on first use, so the shortcuts are live in every
--    buffer, including buffers that gitsigns has not attached to yet.
--    `require('gitsigns')` is called inside the callback, not while the
--    spec is being parsed, so the module is not loaded before the plugin
--    itself is.
--
-- The `mode` field matters for the visual-mode mappings: gitsigns needs the
-- selected line range, and a mapping registered for mode `x` only runs in
-- Visual and Select mode.
--
-- The range is built from `vim.fn.line('.')` and `vim.fn.line('v')`. Those
-- are the two ends of the selection: `v` is the line the selection started
-- on, `.` is the line the cursor is on. gitsigns sorts the pair itself, so
-- a backwards selection produces the same hunk as a forwards one.
--
-- Actions that need a git-backed buffer are safe to invoke elsewhere:
-- gitsigns' actions return early when the current buffer is not attached
-- (lua/gitsigns/cache.lua guards on the buffer cache), and `diffthis`
-- bails out the same way (lua/gitsigns/actions/diffthis.lua). They fail
-- silently rather than raising an error.

local function hunk_range()
  return { vim.fn.line("."), vim.fn.line("v") }
end

return {
  "lewis6991/gitsigns.nvim",
  keys = {
    -- Stage / reset a single hunk.
    {
      "<leader>hs",
      function()
        require("gitsigns").stage_hunk()
      end,
      mode = "n",
      desc = "Gitsigns Stage Hunk",
    },
    {
      "<leader>hr",
      function()
        require("gitsigns").reset_hunk()
      end,
      mode = "n",
      desc = "Gitsigns Reset Hunk",
    },
    {
      "<leader>hs",
      function()
        require("gitsigns").stage_hunk(hunk_range())
      end,
      mode = "v",
      desc = "Gitsigns Stage Hunk",
    },
    {
      "<leader>hr",
      function()
        require("gitsigns").reset_hunk(hunk_range())
      end,
      mode = "v",
      desc = "Gitsigns Reset Hunk",
    },

    -- Stage / reset the whole buffer.
    {
      "<leader>hS",
      function()
        require("gitsigns").stage_buffer()
      end,
      mode = "n",
      desc = "Gitsigns Stage Buffer",
    },
    {
      "<leader>hR",
      function()
        require("gitsigns").reset_buffer()
      end,
      mode = "n",
      desc = "Gitsigns Reset Buffer",
    },

    -- Preview.
    {
      "<leader>hp",
      function()
        require("gitsigns").preview_hunk()
      end,
      mode = "n",
      desc = "Gitsigns Preview Hunk",
    },
    {
      "<leader>hi",
      function()
        require("gitsigns").preview_hunk_inline()
      end,
      mode = "n",
      desc = "Gitsigns Preview Hunk Inline",
    },

    -- Blame.
    {
      "<leader>hb",
      function()
        require("gitsigns").blame_line({ full = true })
      end,
      mode = "n",
      desc = "Gitsigns Blame Line",
    },

    -- Diff.
    {
      "<leader>hd",
      function()
        require("gitsigns").diffthis()
      end,
      mode = "n",
      desc = "Gitsigns Diff This",
    },
    {
      "<leader>hD",
      function()
        require("gitsigns").diffthis("~")
      end,
      mode = "n",
      desc = "Gitsigns Diff This ~",
    },

    -- Quickfix list of hunks.
    --
    -- `setqflist` takes a target: a buffer number, "attached", or "all".
    -- "all" covers every repository the session knows about, which is the
    -- useful default here; the plain mapping uses the current buffer.
    {
      "<leader>hQ",
      function()
        require("gitsigns").setqflist("all")
      end,
      mode = "n",
      desc = "Gitsigns Hunks (All Repos)",
    },
    {
      "<leader>hq",
      function()
        require("gitsigns").setqflist()
      end,
      mode = "n",
      desc = "Gitsigns Hunks (Buffer)",
    },
  },
}
