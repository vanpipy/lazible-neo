# Workspace strategy: `main` vs `feat/java`

How this repo splits a general-purpose Neovim configuration from a
Java-specialised one, and why the split is done with branches rather than
runtime detection.

**Stack:** Neovim 0.12.1, LazyVim 15.14.0, lazy.nvim (stable).

---

## TL;DR

`main` is the general-purpose configuration. `feat/java` is `main` **plus**
Java tooling. The relationship is strictly additive: every feature on `main`
is present on `feat/java`, and Java is the only difference.

| Branch | Purpose | Java tooling | Python tooling |
|---|---|---|---|
| `main` | general-purpose editor config | none | `pyright`, `ruff` |
| `feat/java` | `main` plus Java workspaces | jdtls + JDK discovery | `pyright`, `ruff` |

The branches differ in exactly three **configuration** files:

| File | `main` | `feat/java` |
|---|---|---|
| `lazyvim.json` | no Java extra | adds `lazyvim.plugins.extras.lang.java` |
| `lua/plugins/lsp.lua` | `jdtls = { enabled = false }` | `jdtls = { enabled = true }` |
| `lua/config/lazy.lua` | no Java import | adds `{ import = "plugins.java" }` |

Plus four files that only exist on `feat/java`:
`lua/java/jdk.lua`, `lua/plugins/java/jdtls.lua` and `tests/probe_java.lua`,
which needs the Java modules to resolve a JDK.

The general-purpose probe lives on both branches:
`tests/probe_branch.sh` and `tests/probe.lua`.

`main` stays completely Java-free. See
[Why `main` needs the explicit exclusion](#why-main-needs-the-explicit-exclusion).

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

Everything `main` has, plus:

- `mfussenegger/nvim-jdtls` and the `lazyvim.plugins.extras.lang.java` extra
- `lua/java/jdk.lua`: discovery of the two JDKs jdtls needs
- `lua/plugins/java/jdtls.lua`: pins the jdtls runtime and declares the
  project's target runtime
- `lua/plugins/lsp.lua`: `jdtls = { enabled = true }`, which is the flip side
  of `main`'s `enabled = false`

### `feat/java` removes

Nothing. The Python extra stays in `lazyvim.json` and the Python servers
stay enabled. A feature that exists on `main` must exist on `feat/java`.

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

`lua/java/jdk.lua` resolves the two JDKs independently.

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

`java.configuration.runtimes` ships with a fixed enum of accepted names
(`mason-schemas/lsp.json` in the installed jdtls, 1.60.0):

```
JavaSE-1.8, JavaSE-9, JavaSE-10, ... JavaSE-21, ... JavaSE-26
```

Note that Java 8 is `JavaSE-1.8`, **not** `JavaSE-8`. The name follows the
`JAVA_VERSION` convention (`1.8.0_432`), where the major version for legacy
releases is the second number.

The name is a **label, not a lookup key**. The server resolves the runtime
by `path`. Measured on jdtls 1.60.0, the observable behaviour is identical
for `JavaSE-1.8`, `JavaSE-8` and an entirely bogus name:

| Runtime name | `List.of` (Java 9+) diagnosed as undefined | Shown by `java.vm.getAllInstalls` |
|---|---|---|
| `JavaSE-1.8` | yes | yes, as `JavaSE-1.8` |
| `JavaSE-8` | yes | yes, as `JavaSE-8` |
| `Totally-Bogus-Name` | yes | yes, as `Totally-Bogus-Name` |

So a mismatched name is not a correctness bug on its own. The name is still
kept accurate because the enum exists so that clients and tooling agree on
a spelling, and because the name is what the user sees when they inspect the
detected VMs.

The same convention drives version detection in `jdk.lua`: a `release` file
of `JAVA_VERSION="1.8.0_432"` yields major version 8, and
`JAVA_VERSION="21.0.13"` yields 21.

---

## Why `main` needs the explicit exclusion

Removing the Java extra from `lazyvim.json` is **not** sufficient to stop
Java tooling from attaching.

mason-lspconfig's `automatic_enable` enables every **installed** mason
package, not just the ones the active extras request. The extras only
control `ensure_installed`, which decides what gets *installed*. The
installed set then decides what gets *enabled*.

So if `jdtls` happens to be installed in the shared mason package store, it
gets enabled even when the Java extra is gone entirely.

Setting `enabled = false` is what makes LazyVim add the server to mason's
`automatic_enable.exclude` list. That is the supported opt-out mechanism, and
it is the mechanism `main` uses:

```lua
-- lua/plugins/lsp.lua on main
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
```

On `feat/java` the same key is flipped to `enabled = true`, because there the
Java tooling is wanted:

```lua
-- lua/plugins/lsp.lua on feat/java
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
```

The exclusion is surgical, and it applies to Java only. Neither branch
touches the Python servers: they are configured by the
`lazyvim.plugins.extras.lang.python` extra, which both branches list in
`lazyvim.json`.

### Why the repo's own `plugins` import must not repeat the extras

The repo's `plugins` import is merged **after** the LazyVim extras, so a
value set in `lua/plugins/lsp.lua` wins over the extra's value for the same
key. Measured on `feat/java` with the Python extra present and the repo's
`lsp.lua` disabling the Python servers:

```
PROBE_SERVER final pyright enabled=false
PROBE_SERVER final ruff   enabled=false
```

That is the reason `feat/java` must not name the Python servers at all. The
extra sets them to `enabled = true`, and the repo's file, being merged later,
would silently override that back to `false`. The file states one fact about
one server, and lets the extra own the rest.

### Measured effect

Measured with `tests/probe_branch.sh`, which runs a real Neovim session
against the checkout under test and reports the clients that actually
attached. See [Verifying a change](#verifying-a-change) for how the probe
works and why its timing rules matter.

| Branch | File opened | Attached clients |
|---|---|---|
| `main` | `.py` | `{ "pyright", "ruff" }` |
| `main` | `.java` | `{}`, `jdtls` absent even though it is installed in mason |
| `feat/java` | `.py` | `{ "pyright", "ruff" }` |
| `feat/java` | `.java` | `{ "jdtls" }` |

The merged server table agrees:

| Server | `main` | `feat/java` |
|---|---|---|
| `jdtls` | `enabled=false` | `enabled=true` |
| `pyright` | `enabled=true` | `enabled=true` |
| `ruff` | `enabled=true` | `enabled=true` |
| `basedpyright` | `enabled=false` | `enabled=false` |
| `ruff_lsp` | `enabled=false` | `enabled=false` |

`basedpyright` and `ruff_lsp` stay disabled on **both** branches, because
the Python extra disables them itself. That is the extra's choice, and this
repo does not override it.

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

Because the relationship is additive, a rebase must never remove a feature
that `main` has. After every rebase, check that `main`'s extras are all
still present on `feat/java`:

```bash
python3 - <<'PY'
import json, subprocess

def extras(ref):
    raw = subprocess.run(
        ["git", "show", f"{ref}:lazyvim.json"], capture_output=True, check=True
    ).stdout
    return set(json.loads(raw)["extras"])

missing = extras("main") - extras("feat/java")
print("missing from feat/java:", sorted(missing) or "none")
PY
```

The command must print `none`. Any other output is a feature that `main`
has and `feat/java` lost, which is exactly the regression this branch layout
is meant to prevent. The reverse difference is expected and must be exactly
`lazyvim.plugins.extras.lang.java`.

If the rebase conflicts, the files most likely to conflict are:

- `lazyvim.json`: both branches change the extras list
- `lua/plugins/lsp.lua`: both branches change it, but in opposite directions
  (`jdtls` enabled vs disabled), so it should apply cleanly
- `lua/plugins/extras/refactoring.lua`: only `main` changes it, so it should
  apply cleanly

Keep `lazy-lock.json` identical on both branches. If a rebase changes it,
take `main`'s version, since the plugin set is the same.

---

## Verifying a change

The refactoring keymaps on `main` are covered by a mini.test suite that
drives a real headless Neovim against the repo and asserts the resulting
buffer content. The harness lives in `tests/`, so a fresh clone can run it
without any setup beyond having the plugins installed:

```bash
tests/run.sh
```

To run a single suite:

```bash
tests/run.sh tests/suites/refactoring.lua
tests/run.sh tests/suites/smoke.lua
```

The first run bootstraps `mini.nvim` into `tests/.deps/mini.nvim` at the
commit pinned in `tests/mini.lock`. `tests/.deps/` is gitignored and holds
all scratch state, so a run leaves the working tree clean.

The harness reaches the repo through a symlink at `$XDG_CONFIG_HOME/nvim`.
`tests/run.sh` recreates that symlink on every run and aborts if it does not
resolve to the repository, because a stale copy would silently validate the
wrong configuration.

The Java side is verified by starting Neovim against a real `.java` file and
checking the attached LSP clients, the `lsp.log` launch attempts, the
diagnostics, and the spawned processes.

### Probing a branch

`tests/probe_branch.sh` runs a real Neovim session against a checkout and
reports the LSP clients that actually attached, plus the merged
`nvim-lspconfig` server table:

```bash
# the current checkout
tests/probe_branch.sh . /tmp/probe.out

# another checkout, for example a worktree of main
tests/probe_branch.sh /path/to/main-worktree /tmp/probe-main.out
```

It accepts an optional third argument, the probe script to run. On
`feat/java`, `tests/probe_java.lua` is a narrower probe that reports the
resolved JDKs and polls specifically for `jdtls`:

```bash
tests/probe_branch.sh . /tmp/probe-java.out tests/probe_java.lua
```

That probe only exists on `feat/java`, because it resolves the JDKs through
the Java modules that `main` does not have.

The probe points `XDG_CONFIG_HOME` at a sandbox whose `nvim/` is a symlink to
the checkout under test. Without that, Neovim loads the live
`~/.config/nvim`, which is a **separate clone** of this repository and would
silently measure the wrong configuration.

The sandbox is removed on exit. jdtls keeps writing into its workspace cache
while it shuts down, so the removal is retried a few times before it gives
up and prints a warning. A leftover sandbox is harmless: it holds only a
jdtls workspace cache, and the next run creates its own.

### Acceptance evidence

Each requirement below was checked by running a real Neovim session with a
real file as its only argument, the way a user opens it. The observed values
are what the tool actually reported, not what the configuration intends.

| Requirement | Branch | Observation |
|---|---|---|
| Python attaches `pyright` and `ruff` | `main` | `clients={ "pyright", "ruff" }` |
| Python attaches `pyright` and `ruff` | `feat/java` | `clients={ "pyright", "ruff" }` |
| Go attaches `gopls` | both | `clients={ "gopls" }` |
| TypeScript and JavaScript attach `vtsls` | both | `clients={ "vtsls" }` |
| YAML attaches `yamlls` | both | `clients={ "yamlls" }` |
| JSON attaches `jsonls` | both | `clients={ "jsonls" }` |
| TeX attaches `texlab` | both | `clients={ "texlab" }` |
| TOML attaches `taplo` | both | `clients={ "taplo" }` |
| Markdown attaches `marksman` | both | `clients={ "marksman" }` |
| Bash attaches `bashls` | both | `clients={ "bashls" }` |
| Dockerfile attaches `dockerls` | both | `clients={ "dockerls" }` |
| Lua attaches `lua_ls` | both | `clients={ "lua_ls" }` |
| A `.java` file attaches nothing | `main` | `clients={}`, `jdtls` absent even though it is installed in mason |
| A `.java` file attaches exactly one `jdtls` | `feat/java` | `jdtls_client_count=1`, `all_clients_on_buffer={ "jdtls" }` |
| `jdtls` is excluded from mason on `main` | `main` | `PROBE_SERVER final jdtls enabled=false` |
| `jdtls` is enabled on `feat/java` | `feat/java` | `PROBE_SERVER final jdtls enabled=true` |
| The Python servers are enabled on both branches | both | `PROBE_SERVER final pyright enabled=true`, `... ruff enabled=true` |
| jdtls runs on a JDK 21+ | `feat/java` | `--java-executable=.../java/21.0.13-tem/bin/java`, reported version `21.0.13` |
| The project targets Java 8 | `feat/java` | `runtimes={ { name = "JavaSE-1.8", path = ".../java/current", default = true } }` |
| jdtls reports the Java 8 runtime | `feat/java` | `java.vm.getAllInstalls` lists `JavaSE-1.8` at `.../java/current`, version `1.8.0_432` |
| A Java 9+ API is an error on a Java 8 target | `feat/java` | `var cannot be resolved to a type`, `List cannot be resolved` |
| `JdtCompile` produces class files | `feat/java` | clean project: `JdtCompile_ok=true`, `class_files=1` (`bin/Main.class`) |
| The build still reports the Java 9 API error | `feat/java` | `var cannot be resolved to a type`, `List cannot be resolved`, and jdtls still writes `class_files=2` |

The rows that cover the Python servers on `feat/java` are the ones that
changed when the branch relationship was made additive. Before that change,
`feat/java` reported `clients={}` for a `.py` file.

Two notes on how these were measured, because both produced misleading
results before they were corrected:

- `java.vm.getAllInstalls` is a jdtls **delegate command**, not a raw LSP
  request method. It has to be sent as `workspace/executeCommand`, so
  `client.request(...)` fails with `Unsupported request method`.
- The jdtls workspace is `<tmpdir>/jdtls-<sha1(cwd basename)>`. A stale
  workspace whose incremental build state no longer matches the sources
  produces zero class files and looks like a broken configuration.

`javac` refuses to write any output when a compilation fails, so the broken
project yields no class files at all. jdtls's Eclipse builder does write
them, which is why the error case still reports `class_files=2`. The class
file count is therefore not a measure of whether the build succeeded. The
diagnostics are.

### Measuring LSP attachment correctly

The "clients" column above was measured in a real Neovim session, with the
file as its only argument, the way a user opens it. Two things about that
measurement are not obvious, and both produced wrong answers before they were
corrected.

#### Where the numbers in this section come from

Every measurement quoted below comes from one of four datasets. They are
listed here so that no figure in this section is unsourced, and so that the
limits of each one are explicit.

| Dataset | What it measures | How it was produced | Size |
|---|---|---|---|
| A. Server `PATH` | the `PATH` a language server actually receives | captured from a real `vim.lsp.start()` spawn, not inferred from the shell | 72 entries |
| B. Composition | the cost of the server's own `PATH` scan | the server's scan re-implemented exactly, over the full `PATH`, the mounted-only and native-only subsets, and the three-step `system32` ladder, each measured on its own | 6 scans |
| C. Server round trips | a real `initialize` against the real server | a real LSP `initialize` frame over stdio to `bash-language-server` 5.6.0, with `PATH` overridden per run | 32 against `bashls`: 14 full, 11 trimmed, 4 patched toggle runs, 3 for the `system32` ladder; 34 against `marksman`/`yamlls`/`pyright`; 24 against `jdtls` |
| D. Attach sessions | when `bashls` attaches in a real editor | 40 real `nvim` sessions, each launched with a `.sh` file as its only argument, sampled every two seconds | 40 sessions |

Three rules keep these datasets comparable, and all three were violated at some
point while this was being written, which is why the earlier numbers did not
compose:

1. **The phases run sequentially.** The Windows mount is a shared bottleneck.
   Two `PATH` scans running at the same time slow each other down, so a
   range measured concurrently with another one cannot be compared against it.
   Every phase in dataset B and C runs alone.
2. **The `PATH` is the server's, not the shell's.** Dataset A exists because
   the shell's `PATH` and the server's differ, and only the server's is what
   the server scans.
3. **A rule's verdict and its attach time come from the same session.**
   Dataset D records the full client set on every sample, and each probe rule
   is replayed against those recordings. A rule cannot be graded on one
   session and timed on another.

**1. The probe must not block the event loop.**

A probe driven by `vim.wait(...)` inside a `-c "luafile ..."` command blocks
the event loop for the whole wait. `VimEnter` is only fired once the startup
commands have returned, and `vim.lsp.enable` only starts clients for
pre-existing buffers after that, so nothing attaches and the probe reports
`clients={}` for every file.

This has nothing to do with headless mode. A controlled 2x2 comparison of
transport (headless vs pty) against probe style (blocking vs deferred), all
four running the same configuration against the same `.py` file, gives:

| Transport | Probe | `vim_did_enter` | Attached clients |
|---|---|---|---|
| headless | `vim.wait` | 0 | none |
| pty | `vim.wait` | 0 | none |
| headless | `vim.defer_fn` | 1 | `pyright`, `ruff` |
| pty | `vim.defer_fn` | 1 | `pyright`, `ruff` |

Headless and pty give the same answer in every row. The discriminator is
whether the probe lets the event loop run. `vim.defer_fn` does, `vim.wait`
does not. Note also that `did_filetype()` is 0 in the rows that work: it is
not the signal to look at.

**2. The probe must wait for the servers, not for a fixed short delay.**

Servers do not all become ready at the same time. `bash-language-server` needs
**about ten seconds** to answer `initialize` on this machine, and it is the only
server in the matrix that does. A probe that samples once after a few seconds
therefore reports `bashls` as missing, even though it attaches correctly. The
exact figure moves with how warm the Windows mount is, so treat any single
number as a sample rather than a constant.

The delay is **not** tree-sitter. `bash-language-server` 5.6.0 answers
`initialize` from `out/cli.js`, which awaits `BashServer.initialize()`, which
does two expensive things in order:

| Step | Cost on this machine |
|---|---|
| `initializeParser()`: `Parser.init()` + `Language.load(tree-sitter-bash.wasm)` | **18 ms** |
| `Executables.fromPath(PATH)`: `lstat` on every child of every `PATH` directory | **9.9 s** |

Both steps are measured in the same process, in the same order
`BashServer.initialize()` uses them, so the split is direct rather than
inferred. The `PATH` scan is **99.8%** of the two steps combined: 99.82% for
the scan and 0.18% for tree-sitter.

The scan walks `PATH` and `lstat`s every entry in every directory. The `PATH`
the server actually receives has 72 entries, 26 of them Windows-mounted under
`/mnt/*`. The server only descends into entries that `lstat` reports as real
directories, so those 72 entries break down as:

| Kind | Count | Scanned? |
|---|---|---|
| Real directories under `/mnt/*` | 25 | yes |
| Real directories outside `/mnt/*` | 42 | yes |
| Symlinks (`/bin`, `/sbin`) | 2 | no, `lstat` does not follow them |
| Missing paths | 3 | no, they do not exist |

25 + 42 + 2 + 3 = 72. The 25 mounted directories hold 5870 children and cost
9.9 s when they are measured on their own. The 42 native Linux directories
hold 2159 children and cost 131 ms when measured on their own, with no
Windows mount competing for the same metadata traffic. `/mnt/c/Windows/system32`
alone has 4864 children and accounts for most of the total.

The `lstat` per child is what costs, not the directory read. On
`/mnt/c/Windows/system32`, `readdir` returns all 4864 names in 40 ms, while
`lstat`ing each one takes 10.0 s, roughly 2.0 ms per call. The directory is on
a 9p/DrvFs mount, where every metadata lookup crosses into Windows.

This configuration does not trim `PATH` at all: nothing in `lua/` or
`init.lua` removes entries from it, so the Windows mounts the shell exports
reach the server unchanged. The only `PATH` edit anywhere in the stack is
mason.nvim's, which prepends its own `bin` directory, and that adds one
entry rather than removing any. The delay is therefore a property of the
environment the server is launched into, not of this configuration, and it
would disappear on a machine whose `PATH` has no Windows mounts in it.

Tree-sitter has to be measured cold to get this right. `web-tree-sitter`
memoises its `initPromise`, so calling `Parser.init()` first and timing a
second `initializeParser()` reports 5.1-5.3 ms instead of the real
16.8-21.7 ms. Both numbers are negligible next to the `PATH` scan, but the
cold one is the honest one.

It is also specific to `bashls`. No other server in the matrix scans `PATH`
this way:

| Server | `initialize` with full `PATH` | with `/mnt/*` removed |
|---|---|---|
| `bashls` | **9.9-11.6 s** | 0.34-0.37 s |
| `marksman` | 0.94-1.05 s | 0.95-1.11 s |
| `yamlls` | 0.31-0.37 s | 0.30-0.38 s |
| `pyright` | 0.15-0.17 s | 0.15-0.17 s |
| `jdtls` (`feat/java`) | 3.00-3.17 s | 3.07-3.24 s |

Only `bashls` changes when the Windows mounts are removed. For every other
server the two columns are the same number within run-to-run variation, which
is the point: those servers never look at `PATH` at all. `jdtls` is measured
with the command `feat/java` actually builds,
`mason/bin/jdtls --java-executable=<JDK 21>/bin/java`. It is a JVM and does
not scan `PATH`, so the `/mnt/*` entries do not affect it either way.

Adding only `/mnt/c/Windows/system32` back to a minimal `PATH` restores
almost the entire delay. Measured in one process, in sequence, with the same
instrumented scan and the same real `initialize` round trip:

| `PATH` set | Real dirs | Children | Scan | `initialize` |
|---|---|---|---|---|
| native entries only | 42 | 2159 | 144 ms | **337 ms** |
| native + `system32` | 43 | 7023 | 9647 ms | **9862 ms** |
| the full `PATH` | 67 | 8029 | 9864 ms | **10049 ms** |

One directory out of 43 adds 9525 ms, which is 28 times the 337 ms that all
42 native directories cost together. So the useful conclusion is not "wait
longer" but "the delay comes from `PATH`".

The strongest version of this test patches a **copy** of the server so that
`Executables.fromPath` is skipped, leaving tree-sitter completely untouched,
and toggles the patch at runtime:

| Patched server | `initialize` |
|---|---|
| `PATH` scan on | 10.1 s |
| `PATH` scan off | 0.20 s |
| `PATH` scan off, again | 0.20 s |
| `PATH` scan on, again | 10.0 s |

Only the `PATH` scan moves the number. The tree-sitter parser is still loaded
and still parses in the patched runs; the parse tree for
`echo "hello $name"` is unchanged.

These figures are consistent with the rest of the section rather than measured
separately: an unpatched `initialize` takes 9.9-11.6 s, and turning the scan
off on the same server leaves 0.20 s, so the scan is the 9.7-11.4 s difference
between the two.

The measurement below polls every two seconds until the set of attached
clients has been stable for three consecutive samples, with a minimum window
of 20 seconds and a hard limit of 45. Both parts of that rule matter.

The evidence is 40 real Neovim sessions. Each one is a real `nvim` launched
with a `.sh` file as its only argument, the way a user opens it, and the probe
records the full set of attached clients every two seconds. The attach time is
measured from the moment the process was launched, not from when the probe
started polling. Every session produced an attach, so the dataset has no
failures in it.

`bashls` attached between **9.20 s** and **12.17 s** after launch, with a
median of 10.04 s:

| Attach time | Sessions |
|---|---|
| t=9s | 10 |
| t=10s | 15 |
| t=11s | 3 |
| t=12s | 12 |

So `bashls` was attached by t=10s in 19 of 40 sessions (48%) and by t=12s in 39
of 40 (98%). It is therefore not attached yet when a probe stops at t=6s, and
it is a coin flip whether it is attached by t=10s.

Each rule below was then replayed against those same 40 sessions, so a rule's
verdict and the attach time always come from one session and can never
contradict each other:

| Probe rule | Stops at | False negatives | Correct? |
|---|---|---|---|
| stability only, no minimum window | t=5.2-6.2s | 40 of 40 (100%) | no |
| 10 s window, single sample | t=10s | 21 of 40 (53%) | no |
| 10 s window, 2 stable samples | t=10.2-12.0s | 1 of 40 (3%) | no |
| 20 s window, 3 stable samples | t=20.0-22.0s | 0 of 40 | yes |

Stability alone is not enough: an empty client set is stable from the first
sample, so the probe stops before t=6s and reports `bashls` missing in every
single session. A 10 s window with a single sample is barely better, because
at t=10s `bashls` is attached in fewer than half of the sessions.

The 10 s window with two stable samples fails in exactly one session, the
slowest of the 40, where `bashls` attached at t=12.17s. A 10 s rule is
therefore unreliable by a factor of more than fifty depending on the moment it
runs, which is exactly the property that makes it useless as a test. The 20 s
window passes every run.

The samples are recorded, so a late attach is visible in the result. This is
the slowest of the 40 sessions, the one that makes the two-sample rule fail:

```
t=02s clients=[]
t=04s clients=[]
t=06s clients=[]
t=08s clients=[]
t=10s clients=[]
t=12s clients=[bashls]
t=14s clients=[bashls]
t=16s clients=[bashls]
t=18s clients=[bashls]
t=20s clients=[bashls]
```

A 10 s cutoff is not a safe substitute for the window. Across the sessions
measured above, `bashls` had attached by t=10s in 48% of them and by t=12s in
98% of them, so a probe that stops exactly at 10 s reports `bashls` missing
in roughly one session in two, and the rate moves with how warm the mount is,
which is the worst kind of failure for a test. The same trace under a 20 s
window is stable. The 20 s window is what makes the measurement repeatable,
and the margin is deliberate: the slowest observed attach was t=12.17s, and
the window leaves almost 8 s of headroom before it.

A third mistake, unrelated to the probe: assuming the server needs mason's
`bin` directory on the *shell* `PATH`. It does not. mason.nvim prepends that
directory to `vim.env.PATH` in `setup()`, so the server inherits it from
Neovim. With mason's `bin` directory removed from the shell `PATH`,
`exepath` still resolves `bash-language-server`, `pyright-langserver`,
`ruff`, `taplo`, `marksman` and `yaml-language-server` to their mason
installations, and `pyright` and `ruff` both attach on a `.py` file.

A working measurement therefore needs a probe that keeps the event loop free
and waits for the servers to settle. The `script(1)` command is not enough on
its own, because it does not forward stdin, and Neovim blocks on a "Press
ENTER" prompt when the terminal does not answer its size query.

---

## Environment notes

- The default `java` on `$PATH` is Java 8, and `$JAVA_HOME` points at the
  same Java 8 install. jdtls therefore needs an explicit runtime JDK.
- JDK 21 is available under sdkman, and JDK 8 and 17 as well.
- The mason package store is global. Removing an extra does not uninstall
  anything, which is exactly why the explicit `enabled = false` exclusion is
  required.
- `$PATH` contains 72 entries, 26 of them Windows-mounted directories under
  `/mnt/*`, because this is a WSL environment. `bash-language-server`
  `lstat`s every entry of every `PATH` directory during `initialize`, which
  costs about 10 s here and is the reason `bashls` attaches so much later than
  every other server. See
  [Measuring LSP attachment correctly](#measuring-lsp-attachment-correctly).
