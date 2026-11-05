-- LSP overrides for the `feat/java` branch.
--
-- This branch is `main` PLUS Java. Everything that `main` provides is
-- present here as well, including the Python tooling (`pyright`, `ruff`),
-- which comes from the `lazyvim.plugins.extras.lang.python` extra listed in
-- `lazyvim.json`.
--
-- Exactly one key differs from `main`:
--
--   * `main`      -> `jdtls = { enabled = false }`  (main stays Java-free)
--   * `feat/java` -> `jdtls = { enabled = true }`   (Java support is additive)
--
-- Why the flag exists at all: mason-lspconfig automatically enables every
-- server that is installed in the shared mason package store, regardless of
-- whether the current configuration asks for it. On `main` that would start
-- a jdtls process on a machine that happens to have jdtls installed, even
-- though the Java extra is not part of `main`. LazyVim honours
-- `opts.servers.<name>.enabled = false` by adding the server to Mason's
-- automatic-enablement exclusion list, which is the supported way to opt out.
--
-- On this branch the flag is flipped back to `true`, so that the Java extra
-- and `lua/plugins/java/jdtls.lua` own the jdtls lifecycle. The Java extra
-- installs a `setup.jdtls` handler that returns `true` to skip a duplicate
-- lspconfig-managed client, because `nvim-jdtls` attaches on its own.
--
-- The Python servers are deliberately NOT listed here. They are configured
-- by the Python extra, and this file must not override that configuration.
-- The repo's own `plugins` import is merged AFTER the LazyVim extras, so an
-- `enabled` value set here would win over the extra's.
--
-- See docs/workspace-strategy.md for the measurements behind this.

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        jdtls = { enabled = true },
      },
    },
  },
}
