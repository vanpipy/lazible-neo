-- Language-specific LSP server configuration.
--
-- This branch (feat/java) targets Java workspaces only. The Python tooling is
-- deliberately excluded so that mason-lspconfig's `automatic_enable` cannot
-- re-enable `pyright`/`ruff` just because they happen to be installed in the
-- shared mason package store.
--
-- Why this is needed: mason-lspconfig's `automatic_enable` enables every
-- *installed* mason package, not just the ones the active extras request. The
-- extras only control `ensure_installed` (what gets installed). Removing the
-- Python extra from `lazyvim.json` therefore does NOT stop an already-installed
-- `pyright` from being enabled and attaching to `.py` buffers.
--
-- Setting `enabled = false` makes LazyVim add the server to mason's
-- `automatic_enable.exclude` list, which is the supported way to opt out.
--
-- See docs/workspace-strategy.md for the benchmark that motivated this.

---@type string[]
local disabled_servers = { "pyright", "basedpyright", "ruff", "ruff_lsp" }

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}

      for _, server in ipairs(disabled_servers) do
        opts.servers[server] = opts.servers[server] or {}
        opts.servers[server].enabled = false
      end
    end,
  },
}
