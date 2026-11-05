-- Focused Java probe.
--
-- Reports:
--   * the JDK that `lua/java/jdk.lua` resolves for running jdtls
--   * the JDK that it resolves for the project
--   * whether a `jdtls` client eventually attaches to a `.java` buffer
--
-- jdtls is an Eclipse application. It needs a JDK 21+ to RUN, and it takes
-- noticeably longer than a typical LSP server to start and attach. The
-- probe therefore polls for a bounded period instead of sampling once.

---@param line string
local function emit(line)
  io.stdout:write(line .. "\n")
  io.stdout:flush()
end

---@param ft string
local function collect_clients(ft)
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    names[#names + 1] = client.name
  end
  table.sort(names)
  emit(string.format("JPROBE_CLIENTS %s ft=%s clients=%s", ft, vim.bo.filetype, vim.inspect(names)))
end

local scratch = vim.fn.tempname()
vim.fn.mkdir(scratch .. "/java", "p")
local root = scratch .. "/java/pom.xml"
local rf = assert(io.open(root, "w"))
rf:write("<project></project>\n")
rf:close()
local path = scratch .. "/java/Main.java"
local f = assert(io.open(path, "w"))
f:write(
  'public class Main {\n    public static void main(String[] args) {\n        System.out.println("hello");\n    }\n}\n'
)
f:close()

-- Stage 1: report the resolved JDKs and open the Java file.
vim.defer_fn(function()
  local ok, jdk = pcall(require, "java.jdk")
  if not ok then
    emit("JPROBE_JDK error: " .. tostring(jdk))
  else
    local runtime = jdk.runtime_jdk()
    local project = jdk.project_jdk()
    emit(string.format("JPROBE_JDK runtime=%s", runtime and (runtime.home .. " (v" .. runtime.version .. ")") or "nil"))
    emit(string.format("JPROBE_JDK project=%s", project and (project.home .. " (v" .. project.version .. ")") or "nil"))
    local runtimes = jdk.runtimes()
    emit("JPROBE_RUNTIMES " .. vim.inspect(runtimes))
  end

  emit("JPROBE_JAVA_ON_PATH " .. tostring(vim.fn.exepath("java")))
  local nvim_jdtls = require("lazy.core.config").plugins["nvim-jdtls"]
  emit("JPROBE_NVIM_JDTLS " .. (nvim_jdtls and tostring(nvim_jdtls._.loaded ~= nil) or "missing"))

  vim.cmd("edit " .. vim.fn.fnameescape(path))
end, 4000)

-- Stage 2: poll for the jdtls client.
local elapsed = 0
local step = 3000
local function poll()
  elapsed = elapsed + step
  collect_clients("java@" .. elapsed)
  local attached = false
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    if client.name == "jdtls" then
      attached = true
    end
  end
  if attached or elapsed >= 60000 then
    emit("JPROBE_DONE attached=" .. tostring(attached) .. " elapsed=" .. elapsed)
    -- Stop the servers before quitting. Neovim exiting does not wait for
    -- the jdtls JVM, and a JVM that is still running recreates the
    -- sandbox directories that the cleanup has already removed.
    for _, client in ipairs(vim.lsp.get_clients()) do
      pcall(function()
        client.stop(true)
      end)
    end
    vim.defer_fn(function()
      vim.cmd("qa!")
    end, 2000)
    return
  end
  vim.defer_fn(poll, step)
end
vim.defer_fn(poll, step)
