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
| `main` | general-purpose editor config | none | `pyright`, `ruff` |
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
- `lua/java/jdk.lua`: discovery of the two JDKs jdtls needs
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

Counting the `Starting RPC client` entries in `lsp.log`, which is one line per
server process launch, with the branch's `lua/plugins/lsp.lua` removed and then
restored:

| Branch | File opened | With `lsp.lua` | Without `lsp.lua` |
|---|---|---|---|
| `feat/java` | `.py` | ruff=**0**, pyright=**0** | ruff=**1**, pyright=**1** |
| `feat/java` | `.java` | jdtls=**1** | jdtls=**1** |

Removing the exclusion lets the Python servers launch again. Keeping it does
not affect the Java server.

The attached clients agree with the launch counts: opening the same `.py` file
gives `clients={}` with the exclusion and `clients={ "pyright", "ruff" }`
without it.

Count the `Starting RPC client` lines, not every line that mentions a server
name. A server's stderr is also copied into `lsp.log`, so a plain mention
count overstates the number of launches (a single jdtls session produced four
`mason/bin/jdtls` mentions but only one launch).

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

### Acceptance evidence

Each requirement below was checked by running a real Neovim session with a
real file as its only argument, the way a user opens it. The observed values
are what the tool actually reported, not what the configuration intends.

| Requirement | Branch | Observation |
|---|---|---|
| Python attaches `pyright` and `ruff` | `main` | `clients={ "pyright", "ruff" }` |
| Python attaches nothing | `feat/java` | `clients={}`, neither `pyright` nor `ruff` present |
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
| jdtls runs on a JDK 21+ | `feat/java` | `--java-executable=.../java/21.0.13-tem/bin/java`, reported version `21.0.13` |
| The project targets Java 8 | `feat/java` | `runtimes={ { name = "JavaSE-1.8", path = ".../java/current", default = true } }` |
| jdtls reports the Java 8 runtime | `feat/java` | `java.vm.getAllInstalls` lists `JavaSE-1.8` at `.../java/current`, version `1.8.0_432` |
| A Java 9+ API is an error on a Java 8 target | `feat/java` | `var cannot be resolved to a type`, `List cannot be resolved` |
| `JdtCompile` produces class files | `feat/java` | clean project: `JdtCompile_ok=true`, `class_files=1` (`bin/Main.class`) |
| The build still reports the Java 9 API error | `feat/java` | `var cannot be resolved to a type`, `List cannot be resolved`, and jdtls still writes `class_files=2` |

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
**seven to fourteen seconds** to answer `initialize` on this machine, and it is
the only server in the matrix that does. A probe that samples once after a few
seconds therefore reports `bashls` as missing, even though it attaches
correctly. The exact figure moves with how warm the Windows mount is, so
treat any single number as a sample rather than a constant.

The delay is **not** tree-sitter. `bash-language-server` 5.6.0 answers
`initialize` from `out/cli.js`, which awaits `BashServer.initialize()`, which
does two expensive things in order:

| Step | Cost on this machine |
|---|---|
| `initializeParser()`: `Parser.init()` + `Language.load(tree-sitter-bash.wasm)` | **15-24 ms** |
| `Executables.fromPath(PATH)`: `lstat` on every child of every `PATH` directory | **7-14 s** |

The second step is **99.8%** of the delay: across 10 cold fresh-process
measurements the `PATH` scan accounted for 99.69% to 99.86% of the two
steps combined, and tree-sitter for the remaining 0.14% to 0.31%. The two are
measured in the same process, so the ratio is direct rather than inferred.
The absolute numbers move with how warm the Windows mount is, which is why
the ranges are wide.

The scan walks `PATH` and `lstat`s every entry in every directory. The
`PATH` the server actually receives has 75 entries, 25 of them
Windows-mounted under `/mnt/*`. The 25 mounted directories hold 5870 children
and cost 9.7-13.0 s combined; the 45 native Linux directories hold 2228
children and cost 201-281 ms combined. `/mnt/c/Windows/system32` alone has
4864 children and accounts for most of the total, measuring 6.7-10.1 s
across runs depending on how warm the mount is.

The `lstat` per child is what costs, not the directory read. On
`/mnt/c/Windows/system32`, `readdir` returns all 4864 names in 24-42 ms,
while `lstat`ing each one takes 6.7-10.0 s, roughly 1.4-2.1 ms per call. The
directory is on a 9p/DrvFs mount, where every metadata lookup crosses into
Windows.

This configuration does not trim `PATH` at all: nothing in `lua/` or
`init.lua` removes entries from it, so the Windows mounts the shell exports
reach the server unchanged. The only `PATH` edit anywhere in the stack is
mason.nvim's, which prepends its own `bin` directory, and that adds one
entry rather than removing any. The delay is therefore a property of the
environment the server is launched into, not of this configuration, and it
would disappear on a machine whose `PATH` has no Windows mounts in it.

Tree-sitter has to be measured cold to get this right. `web-tree-sitter`
memoises its `initPromise`, so calling `Parser.init()` first and timing a
second `initializeParser()` reports 5-7 ms instead of the real 15-24 ms. Both
numbers are negligible next to the `PATH` scan, but the cold one is the
honest one.

It is also specific to `bashls`. No other server in the matrix scans `PATH`
this way:

| Server | `initialize` with full `PATH` | with `/mnt/*` removed |
|---|---|---|
| `bashls` | **6.7-13.9 s** | 0.29-0.39 s |
| `marksman` | 1.05-1.60 s | 1.05-1.28 s |
| `yamlls` | 0.32-0.49 s | 0.31-0.35 s |
| `pyright` | 0.15-0.18 s | 0.15-0.19 s |
| `jdtls` (`feat/java`) | 3.19-4.40 s | 3.37-3.85 s |

`jdtls` is measured with the command `feat/java` actually builds,
`mason/bin/jdtls --java-executable=<JDK 21>/bin/java`. It is a JVM and does
not scan `PATH`, so the `/mnt/*` entries do not affect it either way.

Adding only `/mnt/c/Windows/system32` back to a minimal `PATH` restores the
full delay. So the useful conclusion is not "wait longer" but "the delay comes
from `PATH`".

The strongest version of this test patches a **copy** of the server so that
`Executables.fromPath` is skipped, leaving tree-sitter completely untouched,
and toggles the patch at runtime:

| Patched server | `initialize` |
|---|---|
| `PATH` scan on | 7.0-10.9 s |
| `PATH` scan off | 0.18-0.22 s |
| `PATH` scan off, again | 0.18-0.22 s |
| `PATH` scan on, again | 7.0-10.9 s |

Only the `PATH` scan moves the number. The tree-sitter parser is still loaded
and still parses in the patched runs; the parse tree for
`echo "hello $name"` is unchanged.

The measurement below polls every two seconds until the set of attached
clients has been stable for three consecutive samples, with a minimum window
of 20 seconds and a hard limit of 45. Both parts of that rule matter. Across
55 measured sessions `bashls` attached at t=6s, t=8s, t=10s or t=12s (27
sessions at t=8s, 17 at t=10s, 10 at t=12s), so it is not attached yet when
a probe stops at t=6s and only sometimes attached by t=10s.

Each rule below was run repeatedly against the same real session:

| Probe rule | Stops at | False negatives | Correct? |
|---|---|---|---|
| stability only, no minimum window | t=06s | 5 of 5 | no |
| 10 s window, single sample | t=10s | 22 of 32 (69%) | no |
| 10 s window, 2 stable samples | t=10-12s | 16 of 40 (40%) | no |
| 20 s window, 3 stable samples | t=20s | 0 of 21 | yes |

The false-negative rate depends on how warm the Windows mount is, because
that moves the attach time. Early in a session the mount is warm and
`bashls` tends to attach by t=8s or t=10s; later it is slower and attaches
at t=12s or later. A 10 s rule therefore fails somewhere between 4% and 69%
of the time depending on the moment it runs, which is exactly the property
that makes it useless as a test. The 20 s window passes every run.

The samples are recorded, so a late attach is visible in the result:

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
measured above, `bashls` had attached by t=10s in 82% of them and by t=12s in
all of them, so a probe that stops exactly at 10 s reports `bashls` missing
in roughly one session in five, and the rate moves with how warm the mount
is, which is the worst kind of failure for a test. The same trace under a 20 s
window is stable. The 20 s window is what makes the measurement repeatable,
and the margin is deliberate: the slowest observed attach was t=12s, and the
window leaves another 8 s of headroom before it.

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
- `$PATH` contains 26 Windows-mounted directories under `/mnt/*`, because this
  is a WSL environment. `bash-language-server` `lstat`s every entry of every
  `PATH` directory during `initialize`, which costs 7-14 s here and is the
  reason `bashls` attaches so much later than every other server. See
  [Measuring LSP attachment correctly](#measuring-lsp-attachment-correctly).
