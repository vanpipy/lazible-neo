# Workspace strategy: `main` vs `feat/java`

How this repo splits a general-purpose Neovim configuration from a
Java-specialised one, and why the split is done with branches rather than
runtime detection.

**Stack:** Neovim 0.12.1, LazyVim 15.14.0, lazy.nvim (stable).

---

## TL;DR

`main` is the general-purpose configuration. `feat/java` adds Java tooling on
top of it and removes the Python tooling that would otherwise compete for the
same buffers.

| Branch | Purpose | Java tooling | Python tooling |
|---|---|---|---|
| `main` | general-purpose editor config | none | none |
| `feat/java` | Java workspaces | jdtls + JDK discovery | explicitly disabled |

The split is **not** achieved by removing the Python extra alone. See
[Why the explicit exclusion is load-bearing](#why-the-explicit-exclusion-is-load-bearing).

---

## The rule: what goes where

### `main` keeps

Tooling that is useful in most projects and has no heavyweight runtime
dependency:

- Python (`pyright`, `ruff`, `venv-selector`)
- Go (`gopls`)
- JavaScript / TypeScript (`ts_ls`, `eslint`)
- LaTeX (`texlab`), YAML, JSON, TOML, Markdown, Tailwind, Docker
- Editing and refactoring tooling that is language-agnostic:
  `snacks.nvim`, `mini.surround`, `dial`, `yanky`, `refactoring.nvim`,
  `diffview`

### `feat/java` adds

- `mfussenegger/nvim-jdtls` and the `lazyvim.plugins.extras.lang.java` extra
- `lua/plugins/java/jdk.lua`: discovery of the two JDKs jdtls needs
- `lua/plugins/java/jdtls.lua`: pins the jdtls runtime and declares the
  project's target runtime
- `lua/plugins/lsp.lua`: explicit `enabled = false` for the Python servers

### `feat/java` removes

- The `lazyvim.plugins.extras.lang.python` extra
- Explicit enablement of `pyright`, `basedpyright`, `ruff` and `ruff_lsp`

The `lazy-lock.json` is **byte-identical** between the two branches, so
switching branches never churns plugin versions.

---

## The two JDKs

jdtls needs two different JDKs, and conflating them is the classic cause of
"jdtls does not start" and "wrong language level" bugs.

| Role | Requirement | Set by |
|---|---|---|
| The JDK that **runs** jdtls | 21 or newer | `--java-executable` in the `cmd` |
| The JDK the **project** targets | 8 or newer | `settings.java.configuration.runtimes` |

jdtls is an Eclipse application and its launcher refuses to start on
anything older than 21:

```
Exception: jdtls requires at least Java 21
```

That check lives in mason's `jdtls/bin/jdtls.py` and applies to whichever
`java` the launcher resolves. Because the launcher's own flag is used
(`--java-executable=<path>`), the version check applies to the JDK that was
chosen rather than to whatever happens to be first on `$PATH`.

This matters on this machine specifically. The default `java` on `$PATH` is
Java 8:

```
$ java -version
openjdk version "1.8.0_432"
OpenJDK Runtime Environment (Temurin)(build 1.8.0_432-b06)
```

so an unconfigured jdtls would never start here.

The project's target JDK is passed through the standard
`java.configuration.runtimes` preference, which is what determines the
language level and the platform classes that completion and diagnostics see.

### Discovery order

`lua/plugins/java/jdk.lua` resolves the two JDKs independently.

Runtime JDK (21+):

1. `$JDTLS_JAVA_HOME`, if it is actually new enough
2. `$JAVA_HOME`, if it is 21 or newer
3. a known JDK 21+ install, then a glob over common install roots
4. `java` on `$PATH`, if it is 21 or newer

Project JDK (8+):

1. `$JAVA_PROJECT_HOME`, if it is actually usable
2. `$JAVA_HOME`, if it is 8 or newer
3. the sdkman `current` candidate
4. a known JDK 8+ install, then a glob over common install roots

An override that is too old is **ignored** rather than trusted, because
honouring it would make jdtls refuse to start.

### Runtime naming

`java.configuration.runtimes` requires each entry's `name` to come from a
fixed enum. jdtls 1.60.0 ships this list:

```
JavaSE-1.8, JavaSE-9, JavaSE-10, ... JavaSE-21, ... JavaSE-26
```

Note that Java 8 is `JavaSE-1.8`, **not** `JavaSE-8`. The name follows the
`JAVA_VERSION` convention (`1.8.0_432`), where the major version for legacy
releases is the second number. A name outside the enum is rejected by the
server, which then falls back to its own detected JDKs and silently ignores
the intended target.

The same convention drives version detection in `jdk.lua`: a `release` file
of `JAVA_VERSION="1.8.0_432"` yields major version 8, and
`JAVA_VERSION="21.0.13"` yields 21.

---

## Why the explicit exclusion is load-bearing

Removing the Python extra from `lazyvim.json` is **not** sufficient to stop
Python tooling from attaching.

mason-lspconfig's `automatic_enable` enables every **installed** mason
package, not just the ones the active extras request. The extras only
control `ensure_installed`, which decides what gets *installed*. The
installed set then decides what gets *enabled*.

So if `pyright` happens to be installed in the shared mason package store, it
gets enabled even when the Python extra is gone entirely.

Setting `enabled = false` is what makes LazyVim add the server to mason's
`automatic_enable.exclude` list. That is the supported opt-out mechanism, and
it is the mechanism `feat/java` uses:

```lua
-- lua/plugins/lsp.lua
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
```

The exclusion is surgical. Each branch still launches its **own** language's
server normally.

### Measured effect

Counting server launch attempts recorded in `lsp.log`, with the branch's
`lua/plugins/lsp.lua` removed and then restored:

| Branch | File opened | With `lsp.lua` | Without `lsp.lua` |
|---|---|---|---|
| `feat/java` | `.py` | ruff=**0** | ruff=**7** |
| `feat/java` | `.java` | jdtls=1 | jdtls=1 |

Removing the exclusion lets the Python server launch again. Keeping it does
not affect the Java server.

---

## Why branches rather than runtime detection

### `recommended` is display-only

LazyVim computes the `recommended` flag purely for the `:Extras` UI. Nothing
outside the extras module consumes it. A recommended extra does not
auto-load anything.

### Extras cost almost nothing at parse time

An extra's plugin specs are parsed at startup, but the plugins themselves
carry their own lazy triggers, so they load only when a matching file is
opened. This is why startup time is flat across configurations.

### `cond` is evaluated at spec-parse time

lazy.nvim evaluates a plugin's `cond` during `Meta:resolve()`, which runs
inside `lazy.setup()`, **before any file is opened**. The loader then
refuses to load any plugin whose `cond` resolved to `false`.

A `cond` that inspects the current buffer therefore always sees an empty
buffer. Runtime gating has to happen in `opts`, which is evaluated at
plugin-load time, after the file is open. This is a sharp edge that makes
runtime detection easy to get subtly wrong.

### Branches make behaviour explicit and reviewable

A branch's behaviour is fully determined by its committed `lazyvim.json` and
`lua/plugins/lsp.lua`. A runtime-detected config depends on the working
directory at launch, which is exactly the kind of state that is hard to
review and easy to get wrong.

---

## Working on the two branches

`main` is the base. `feat/java` is rebuilt from it:

```bash
# on main, after merging the general-purpose changes
git checkout main

# rebuild the Java branch from the updated main
git checkout feat/java
git rebase main
```

Rebasing rather than merging keeps the Java branch's history a linear
sequence of Java-specific commits on top of `main`.

If the rebase conflicts, the files most likely to conflict are:

- `lazyvim.json`: both branches change the extras list
- `lua/plugins/lsp.lua`: only `feat/java` changes it, so it should apply
  cleanly
- `lua/plugins/extras/refactoring.lua`: only `main` changes it, so it should
  apply cleanly

Keep `lazy-lock.json` identical on both branches. If a rebase changes it,
take `main`'s version, since the plugin set is the same.

---

## Verifying a change

The refactoring keymaps on `main` are covered by a mini.test suite that
drives a real headless Neovim against the repo and asserts the resulting
buffer content:

```bash
cd /tmp/lazytest/rfvalidate
bash run_tests.sh tests/test_refactoring.lua
bash run_tests.sh tests/test_smoke.lua
```

The harness reaches the repo through a symlink at `$XDG_CONFIG_HOME/nvim`.
`run_tests.sh` recreates that symlink on every run and aborts if it does not
resolve to the repository, because a stale copy would silently validate the
wrong configuration.

The Java side is verified by starting Neovim against a real `.java` file and
checking the attached LSP clients, the `lsp.log` launch attempts, the
diagnostics, and the spawned processes.

---

## Environment notes

- The default `java` on `$PATH` is Java 8, and `$JAVA_HOME` points at the
  same Java 8 install. jdtls therefore needs an explicit runtime JDK.
- JDK 21 is available under sdkman, and JDK 8 and 17 as well.
- The mason package store is global. Removing an extra does not uninstall
  anything, which is exactly why the explicit `enabled = false` exclusion is
  required.
