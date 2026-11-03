--- Java toolchain discovery for the `feat/java` branch.
---
--- jdtls needs TWO different JDKs, and conflating them is the classic
--- source of "jdtls does not start" / "wrong language level" bugs:
---
---  1. The JDK that RUNS jdtls. jdtls is an Eclipse application that
---     requires Java 21 or newer. Its launcher refuses to start otherwise:
---       `Exception: jdtls requires at least Java 21`
---     (mason's `jdtls/bin/jdtls.py`, `get_java_executable`).
---     This is the JDK that must be 21+.
---
---  2. The JDK that the PROJECT is compiled and analyzed against. This is
---     the one that determines the language level (Java 8 here) and which
---     `rt.jar` / platform classes the completion and diagnostics see.
---     This is passed to jdtls via `settings.java.configuration.runtimes`.
---
--- Keeping (1) and (2) separate is what makes a Java 8 project work while
--- jdtls itself runs on a modern JDK.
---
--- Resolution order for the RUNTIME JDK (21+):
---   1. `$JDTLS_JAVA_HOME`            (explicit override, wins over everything)
---   2. `$JAVA_HOME`                  (if it is 21 or newer)
---   3. a JDK 21+ found in the well-known locations below
---   4. `java` on `$PATH`             (if it is 21 or newer)
---
--- Resolution order for the PROJECT JDK:
---   1. `$JAVA_PROJECT_HOME`          (explicit override)
---   2. `$JAVA_HOME`                  (if it is 8 or newer)
---   3. the sdkman `current` candidate
---   4. a JDK 8+ found in the well-known locations below
---
--- Both can be overridden per-project, and both are also overridable at
--- runtime through the standard `settings.java.configuration.runtimes`
--- preference that jdtls understands natively.

local M = {}

---@class JavaJdk
---@field home string      -- absolute path to the JDK home (the dir containing `bin/java`)
---@field version number   -- major version, e.g. 8 or 21
---@field source string    -- absolute path to `src.zip`, if present

--- Directories that commonly hold a JDK installation.
--- Ordered so that "real" system installs win over tool-managed ones.
---@type string[]
local known_jdk_homes = {
  "$HOME/.local/opt/jdk/temurin-21",
  "$HOME/.local/opt/jdk/temurin-17",
  "$HOME/.local/opt/jdk/temurin-11",
  "$HOME/.local/opt/jdk/temurin-8",
  "$HOME/.sdkman/candidates/java/current",
  "$HOME/.sdkman/candidates/java/21.0.8-tem",
  "$HOME/.sdkman/candidates/java/17.0.12-tem",
  "$HOME/.sdkman/candidates/java/11.0.21-tem",
  "$HOME/.sdkman/candidates/java/8.0.412-tem",
  "/usr/lib/jvm/temurin-21-jdk",
  "/usr/lib/jvm/temurin-17-jdk",
  "/usr/lib/jvm/temurin-11-jdk",
  "/usr/lib/jvm/temurin-8-jdk",
  "/usr/lib/jvm/java-21-openjdk",
  "/usr/lib/jvm/java-17-openjdk",
  "/usr/lib/jvm/java-11-openjdk",
  "/usr/lib/jvm/java-8-openjdk",
  "/usr/lib/jvm/default-java",
  "/usr/lib/jvm/java",
}

--- Glob patterns for JDK installations whose exact directory name is not
--- predictable (sdkman version strings, distro package names, ...).
--- Every match is probed, so a non-JDK directory is simply skipped.
---@type string[]
local jdk_glob_patterns = {
  "$HOME/.sdkman/candidates/java/*",
  "$HOME/.local/opt/jdk/*",
  "/usr/lib/jvm/*",
  "/usr/java/*",
  "/opt/java/*",
  "/Library/Java/JavaVirtualMachines/*/Contents/Home",
}

--- Expand a leading `$HOME` / `~` in a path.
---@param path string
---@return string
local function expand(path)
  if path == nil or path == "" then
    return ""
  end
  path = path:gsub("^~([^/]*)", function(rest)
    return vim.env.HOME .. rest
  end)
  path = path:gsub("^%$HOME", vim.env.HOME or "")
  path = path:gsub("^%$", "")
  return path
end

--- Read the major version of a JDK from its `release` file (JDK 9+).
---@param home string
---@return number?
local function version_from_release_file(home)
  local file = io.open(home .. "/release", "r")
  if not file then
    return nil
  end
  local content = file:read("*a")
  file:close()
  -- e.g. JAVA_VERSION="21.0.13" or JAVA_VERSION="1.8.0_512"
  local version = content:match('JAVA_VERSION="([^"]+)"')
  if not version then
    return nil
  end
  local major = version:match("^(%d+)%.(%d+)") or version:match("^(%d+)")
  if not major then
    return nil
  end
  -- Legacy "1.8.0_512" scheme: the major is the SECOND number.
  if version:match("^1%.%d+") then
    major = version:match("^1%.(%d+)")
  end
  return tonumber(major)
end

--- Read the major version of a JDK 8 by running its `java -version`.
--- Java 8 has no `release` file, so `java -version` is the only reliable source.
---@param home string
---@return number?
local function version_from_java_binary(home)
  local java = home .. "/bin/java"
  if vim.fn.executable(java) == 0 then
    return nil
  end
  local ok, output = pcall(vim.fn.system, { java, "-version" })
  if not ok or vim.v.shell_error ~= 0 then
    return nil
  end
  -- "openjdk version \"1.8.0_512\"" or "openjdk version \"21.0.13\""
  local version = tostring(output):match('version%s+"([^"]+)"')
  if not version then
    return nil
  end
  local major
  if version:match("^1%.%d+") then
    major = version:match("^1%.(%d+)")
  else
    major = version:match("^(%d+)")
  end
  return tonumber(major)
end

--- Build a JDK description for a home directory, if it looks like a usable JDK.
---@param home string
---@return JavaJdk?
local function probe(home)
  if home == "" then
    return nil
  end
  home = expand(home)
  if vim.fn.isdirectory(home) == 0 then
    return nil
  end
  if vim.fn.executable(home .. "/bin/java") == 0 then
    return nil
  end

  -- Prefer the `release` file; fall back to running java (needed for JDK 8).
  local version = version_from_release_file(home) or version_from_java_binary(home)
  if not version then
    return nil
  end

  local source = home .. "/src.zip"
  if vim.fn.filereadable(source) == 0 then
    source = home .. "/lib/src.zip"
  end
  if vim.fn.filereadable(source) == 0 then
    source = nil
  end

  return { home = home, version = version, source = source }
end

--- Find the first JDK at or above `min_version` from the known locations.
---@param min_version number
---@return JavaJdk?
function M.find(min_version)
  for _, candidate in ipairs(known_jdk_homes) do
    local jdk = probe(candidate)
    if jdk and jdk.version >= min_version then
      return jdk
    end
  end

  -- Fall back to globbing, so JDKs installed under a name we did not
  -- anticipate are still found.
  for _, pattern in ipairs(jdk_glob_patterns) do
    local matches = vim.fn.glob(expand(pattern), true, true)
    if type(matches) == "table" then
      table.sort(matches)
      for _, candidate in ipairs(matches) do
        local jdk = probe(candidate)
        if jdk and jdk.version >= min_version then
          return jdk
        end
      end
    end
  end

  return nil
end

--- The JDK that runs jdtls. Must be 21+ for jdtls 1.58.
---@return JavaJdk?
function M.runtime_jdk()
  -- 1. explicit override, but only if it is actually new enough. An
  --    override that is too old would make jdtls refuse to start
  --    ("jdtls requires at least Java 21"), so it is ignored and the
  --    normal discovery chain continues.
  local jdk = probe(vim.env.JDTLS_JAVA_HOME or "")
  if jdk and jdk.version >= 21 then
    return jdk
  end

  -- 2. JAVA_HOME, when new enough
  jdk = probe(vim.env.JAVA_HOME or "")
  if jdk and jdk.version >= 21 then
    return jdk
  end

  -- 3. a known JDK 21+ install
  jdk = M.find(21)
  if jdk then
    return jdk
  end

  -- 4. `java` on $PATH, when new enough
  local on_path = vim.fn.exepath("java")
  if on_path ~= "" then
    jdk = probe(vim.fn.fnamemodify(on_path, ":h:h"))
    if jdk and jdk.version >= 21 then
      return jdk
    end
  end

  return nil
end

--- The JDK that the project is compiled/analyzed against.
---@return JavaJdk?
function M.project_jdk()
  -- 1. explicit override, but only if it is a usable JDK (8+). An
  --    override that is too old or not a JDK at all is ignored so the
  --    normal discovery chain can still find a sane project JDK.
  local jdk = probe(vim.env.JAVA_PROJECT_HOME or "")
  if jdk and jdk.version >= 8 then
    return jdk
  end

  -- 2. JAVA_HOME, when old enough to be a sensible project JDK
  jdk = probe(vim.env.JAVA_HOME or "")
  if jdk and jdk.version >= 8 then
    return jdk
  end

  -- 3. the sdkman `current` candidate (the user's default JDK)
  jdk = probe("$HOME/.sdkman/candidates/java/current")
  if jdk and jdk.version >= 8 then
    return jdk
  end

  -- 4. any JDK 8+
  jdk = M.find(8)
  if jdk then
    return jdk
  end

  return nil
end

--- Build the `settings.java.configuration.runtimes` list.
---
--- jdtls reads this preference directly (verified in the installed
--- `org.eclipse.jdt.ls.core` jar): each entry is a map with the keys
--- `name`, `path` and `default`, and exactly one entry may be the default.
--- The `path` must be the JDK home (the directory containing `bin/java`),
--- not the `bin` directory itself.
---
--- The runtime JDK is intentionally NOT listed as a project runtime: it is
--- the JVM that runs jdtls, not a target for the project's code.
---@return table[]?
function M.runtimes()
  local project = M.project_jdk()
  if not project then
    return nil
  end

  local runtimes = {
    {
      -- Eclipse-style name: the major version, which is what the jdtls
      -- `JdtSetRuntime` command shows and what `JdtCompile` expects.
      name = "JavaSE-" .. project.version,
      path = project.home,
      default = true,
    },
  }

  if project.source then
    runtimes[1].sources = project.source
  end

  return runtimes
end

--- The `java` executable that should RUN jdtls.
---@return string?
function M.runtime_java()
  local jdk = M.runtime_jdk()
  if not jdk then
    return nil
  end
  return jdk.home .. "/bin/java"
end

return M
