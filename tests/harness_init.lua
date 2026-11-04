-- Minimal init for the mini.test harness.
--
-- The child Neovim loads the *real* repo config so the harness exercises the
-- exact plugin specs, keymaps and LSP wiring the user actually runs.
--
-- The repo is reached through `stdpath("config")`. tests/run.sh points
-- XDG_CONFIG_HOME at a sandbox whose `nvim/` is a symlink to the repo, so
-- `stdpath("config") .. "/lua/config/lazy.lua"` resolves inside the repo.
-- This matters because LazyVim reads `stdpath("config") .. "/lazyvim.json"`
-- to decide which extras to load. Loading the repo via rtp alone would still
-- pick up the live ~/.config/nvim's lazyvim.json.
--
-- Three things differ from a normal startup, all required for a headless
-- test:
--   * `checker.enabled = false`, because lazy.nvim's update checker would
--     otherwise try to reach the network from inside the sandbox.
--   * `install.missing = false`, so a missing plugin surfaces as an error
--     instead of a silent network install.
--   * `lazy` is put on the runtimepath before anything requires it, because
--     Neovim starts with a default runtimepath that does not contain the
--     plugin store, and the repo's own `lua/config/lazy.lua` only prepends
--     lazy.nvim inside the module.

local REPO = os.getenv("RF_REPO")
if not REPO then
  error("RF_REPO is not set. Run the suite through tests/run.sh.")
end

vim.cmd("set rtp+=" .. REPO)

-- mini.nvim must be on the runtimepath here, not only in the parent.
--
-- mini.test spawns the child with `--clean`, which resets the runtimepath to
-- Neovim's built-in defaults. Anything the child needs has to be re-added
-- from this init file, because the parent's `-c "lua vim.opt.rtp:prepend(...)"`
-- does not reach the child. Without this line `require("mini.test")` fails
-- during the child's startup, and a headless Neovim that errors during init
-- never exits. It just hangs until the runner's timeout kills it.
vim.cmd("set rtp+=" .. REPO .. "/tests/.deps/mini.nvim")

require("mini.test").setup()

-- Put lazy.nvim on the runtimepath before requiring it, exactly where the
-- repo's config expects to find it.
vim.opt.rtp:prepend(vim.fn.stdpath("data") .. "/lazy/lazy.nvim")

-- Inject the test-only overrides by wrapping `lazy.setup` before the repo's
-- config module calls it.
local lazy = require("lazy")
local orig_setup = lazy.setup
lazy.setup = function(spec, opts)
  opts = opts or {}
  opts.checker = vim.tbl_deep_extend("force", opts.checker or {}, { enabled = false })
  opts.install = vim.tbl_deep_extend("force", opts.install or {}, { missing = false })
  return orig_setup(spec, opts)
end

require("config.lazy")

-- mini.test starts the child with `--headless`, so `UIEnter` never fires.
-- lazy.nvim defers the `VeryLazy` event to `UIEnter` (see lazy/core/util.lua,
-- `Util.very_lazy()`), because it registers the `User LazyDone` handler while
-- `vim.v.vim_did_enter` is still 0 during `-u init.lua`. The consequence is
-- that every plugin registered with `event = "VeryLazy"` (mini.ai among them)
-- never loads in the harness, while an interactive Neovim loads them at
-- `UIEnter`.
--
-- Fire the same event explicitly so the harness exercises the configuration
-- the user actually runs. Scheduled, exactly like lazy.nvim does it.
vim.api.nvim_create_autocmd("VimEnter", {
  once = true,
  callback = function()
    vim.schedule(function()
      vim.g.did_very_lazy = true
      vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
    end)
  end,
})

-- LSP server used by the refactoring fixtures. Upstream's own test setup
-- enables exactly this one for Lua.
--
-- The root marker list matters. `vim.lsp.config` resolves the root by
-- searching upward for the FIRST marker that matches, and the markers are
-- tried in order. The fixture directories under work/ contain a `.git`
-- directory, so `.git` alone would root each fixture correctly.
--
-- But the marker list must not include `stylua.toml` or `.luarc.json`:
-- those files can exist in an ancestor of the harness (for example a
-- stray `stylua.toml` in the harness's own parent directory). When that
-- happens, lua_ls roots the WORKSPACE at that ancestor instead of the
-- fixture directory, `textDocument/definition` cannot resolve a local
-- variable to its declaration, and every LSP-dependent refactoring
-- (inline variable, inline function, select refactor) silently does
-- nothing. The buffer then still holds the original text and the test
-- fails with a confusing "buffer did not match" message.
--
-- `.git` is checked first and is the only marker the fixtures guarantee,
-- so the root is deterministic regardless of what sits above work/.
vim.lsp.config("lua_ls", {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_markers = { ".git" },
})
vim.lsp.enable({ "lua_ls" })
