-- LSP overrides for the general-purpose configuration.
--
-- `main` deliberately stays lightweight and free of Java tooling. Java
-- support lives on the `feat/java` branch, where the JDK helper and the
-- jdtls configuration are kept together.
--
-- Removing `lazyvim.plugins.extras.lang.java` from `lazyvim.json` is not
-- enough on its own: mason-lspconfig automatically enables every server that
-- is installed locally, so a machine with jdtls already present in Mason
-- would still start it (and spawn a jdtls process) even though the extra is
-- gone. LazyVim honours `opts.servers.<name>.enabled = false` by adding the
-- server to Mason's automatic-enablement exclusion list, which is exactly
-- what we need here.
--
-- Keep this file in sync with the `feat/java` branch, where the same key is
-- flipped back to `true` together with the JDK setup.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        jdtls = { enabled = false },
      },
    },
  },
}
