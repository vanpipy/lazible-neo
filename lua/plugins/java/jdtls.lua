--- Java / jdtls configuration for the `feat/java` branch.
---
--- This file overrides the `mfussenegger/nvim-jdtls` spec that comes from
--- the LazyVim `lang.java` extra. Two things are adjusted:
---
---  1. The JVM that RUNS jdtls is forced to a JDK 21+, because jdtls
---     refuses to start on anything older
---     (`Exception: jdtls requires at least Java 21`).
---     The extra's default `cmd` is `{ vim.fn.exepath("jdtls") }`, which
---     resolves `java` through `$JAVA_HOME`/`$PATH`. That is a problem when
---     the shell's default JDK is 8 (a very common setup for legacy Java
---     projects) and jdtls is simply dead.
---
---  2. The JDK the PROJECT is analyzed against is declared through
---     `settings.java.configuration.runtimes`, so completion and
---     diagnostics use the right platform classes and language level.
---
--- Because lazy.nvim merges duplicate plugin specs key by key, the `opts`
--- function below receives the extra's already-computed options and only
--- replaces the parts it needs to. Nothing else from the extra is lost.
---
--- Overrides:
---   `$JDTLS_JAVA_HOME`   -- the JDK 21+ that runs jdtls
---   `$JAVA_PROJECT_HOME` -- the JDK the project targets
---
--- See `lua/java/jdk.lua` for the discovery logic.

local jdk = require("java.jdk")

---@type LazySpec
return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      opts = opts or {}

      -- 1. Make jdtls run on a JDK 21+.
      --
      -- The extra builds `cmd` as `{ vim.fn.exepath("jdtls") }` plus the
      -- lombok javaagent. We keep the same shape but pin the JVM that the
      -- launcher will use, by passing `--java-executable`. This is the
      -- launcher's own supported flag (see `jdtls/bin/jdtls.py`), so the
      -- version check is applied to the JDK we choose.
      local runtime_java = jdk.runtime_java()
      if runtime_java then
        local cmd = opts.cmd or { vim.fn.exepath("jdtls") }
        cmd = vim.deepcopy(cmd)

        -- Drop any previously configured --java-executable so we do not
        -- end up with two conflicting flags.
        local cleaned = {}
        for i = 1, #cmd do
          if cmd[i] ~= "--java-executable" then
            cleaned[#cleaned + 1] = cmd[i]
          elseif cmd[i + 1] then
            i = i + 1 -- also drop the value that followed the flag
          end
        end
        cmd = cleaned

        table.insert(cmd, "--java-executable=" .. runtime_java)
        opts.cmd = cmd
      end

      -- 2. Tell jdtls which JDK the project targets.
      --
      -- `java.configuration.runtimes` is a standard jdtls preference: each
      -- entry has a `name`, a `path` (the JDK home) and a `default` flag.
      -- jdtls resolves the project against the default runtime, which is
      -- what determines the language level and the available platform APIs.
      local runtimes = jdk.runtimes()
      if runtimes then
        opts.settings = opts.settings or {}
        opts.settings.java = opts.settings.java or {}
        opts.settings.java.configuration = opts.settings.java.configuration or {}
        opts.settings.java.configuration.runtimes = runtimes
      end

      return opts
    end,
  },
}
