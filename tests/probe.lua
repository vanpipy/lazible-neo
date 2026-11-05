-- LSP probe for a checkout of this repository.
--
-- Reports, for each probe file type:
--   * the LSP clients that actually attached to a buffer of that type
--   * the merged `nvim-lspconfig` server table with its `enabled` flags
--
-- Four timing rules matter, all learned the hard way:
--
--   1. Everything is observed from a DEFERRED callback (vim.defer_fn).
--      A blocking vim.wait() inside a startup command prevents the LSP
--      client from ever attaching to the buffer, which yields a false
--      "the server did not start" result.
--
--   2. The deferred callback must run AFTER lazy.nvim has finished
--      loading. lazy.nvim defers its `VeryLazy` event to `UIEnter`, which
--      does not fire while `-u init.lua` is still running. Reporting from
--      the startup command therefore observes an empty plugin table.
--
--   3. The buffer must be OPENED in one stage and READ in a later one.
--      `vim.lsp.enable` attaches asynchronously after the filetype is
--      detected, so reading the client list in the same tick as the
--      `:edit` always reports an empty list.
--
--   4. jdtls is an Eclipse application and needs far longer to start than
--      a typical LSP server. The probe POLLS until the expected clients
--      have attached, or until a deadline, instead of sampling once.
--
-- Driven by tests/probe_branch.sh, which points XDG_CONFIG_HOME at a
-- sandbox whose `nvim/` symlinks to the checkout under test.

---@param line string
local function emit(line)
  io.stdout:write(line .. "\n")
  io.stdout:flush()
end

--- Fixture files, one per probe type. Each lives in its own directory with
--- a project root marker, so that servers which require a project root
--- resolve it deterministically.
---
--- `expect` lists the servers that SHOULD attach. An empty list means the
--- probe only records what attached; it does not assert anything.
---@type table<string, { ext: string, body: string, root: string, root_body: string, expect: string[] }>
local fixtures = {
  python = {
    ext = "py",
    body = "import os\n\n\ndef greet(name: str) -> str:\n    return f'hello {name}'\n",
    root = "pyproject.toml",
    root_body = '[project]\nname = "probe"\nversion = "0.0.0"\n',
    expect = { "pyright", "ruff" },
  },
  java = {
    ext = "java",
    body = 'public class Main {\n    public static void main(String[] args) {\n        System.out.println("hello");\n    }\n}\n',
    root = "pom.xml",
    root_body = "<project></project>\n",
    expect = { "jdtls" },
  },
  go = {
    ext = "go",
    body = "package main\n\nfunc main() {}\n",
    root = "go.mod",
    root_body = "module probe\n\ngo 1.21\n",
    expect = { "gopls" },
  },
  typescript = {
    ext = "ts",
    body = "export const answer: number = 42;\n",
    root = "tsconfig.json",
    root_body = "{}\n",
    expect = { "vtsls" },
  },
  yaml = {
    ext = "yaml",
    body = "key: value\n",
    root = "config.yaml",
    root_body = "key: value\n",
    expect = { "yamlls" },
  },
  json = {
    ext = "json",
    body = '{ "key": "value" }\n',
    root = "config.json",
    root_body = "{}\n",
    expect = { "jsonls" },
  },
  tex = {
    ext = "tex",
    body = "\\documentclass{article}\n\\begin{document}\nHello\n\\end{document}\n",
    root = "main.tex",
    root_body = "\\documentclass{article}\n",
    expect = { "texlab" },
  },
  toml = {
    ext = "toml",
    body = '[table]\nkey = "value"\n',
    root = "config.toml",
    root_body = "[table]\n",
    expect = { "taplo" },
  },
  markdown = {
    ext = "md",
    body = "# Heading\n\nSome text.\n",
    root = "README.md",
    root_body = "# Probe\n",
    expect = { "marksman" },
  },
  bash = {
    ext = "sh",
    body = '#!/usr/bin/env bash\necho "hello $name"\n',
    root = "script.sh",
    root_body = "#!/usr/bin/env bash\n",
    expect = { "bashls" },
  },
  dockerfile = {
    ext = "dockerfile",
    body = "FROM alpine\nRUN echo hi\n",
    root = "Dockerfile",
    root_body = "FROM alpine\n",
    expect = { "dockerls" },
  },
  lua = {
    ext = "lua",
    body = "local M = {}\nfunction M.hello() end\nreturn M\n",
    root = "init.lua",
    root_body = "return {}\n",
    expect = { "lua_ls" },
  },
}

---@param name string
local function report_servers(name)
  local plugin = require("lazy.core.config").plugins["nvim-lspconfig"]
  if not plugin then
    emit("PROBE nvim-lspconfig plugin missing")
    return
  end
  local ok, opts = pcall(require("lazy.core.plugin").values, plugin, "opts", false)
  if not ok then
    emit("PROBE opts error: " .. tostring(opts))
    return
  end
  local servers = (opts or {}).servers or {}
  local names = vim.tbl_keys(servers)
  table.sort(names)
  emit("PROBE_SERVERS " .. name)
  for _, server in ipairs(names) do
    local s = servers[server]
    local enabled = "unset"
    if type(s) == "table" and s.enabled ~= nil then
      enabled = tostring(s.enabled)
    end
    emit(string.format("PROBE_SERVER %s %s enabled=%s", name, server, enabled))
  end
  local setup = (opts or {}).setup or {}
  local setup_names = vim.tbl_keys(setup)
  table.sort(setup_names)
  emit(string.format("PROBE_SETUP %s %s", name, vim.inspect(setup_names)))
end

--- Create the fixture files under a scratch directory.
---@param dir string
---@return table<string, string> paths
local function write_fixtures(dir)
  local paths = {}
  for ft, spec in pairs(fixtures) do
    local d = dir .. "/" .. ft
    vim.fn.mkdir(d, "p")
    local root = d .. "/" .. spec.root
    local rf = assert(io.open(root, "w"))
    rf:write(spec.root_body)
    rf:close()
    local path = d .. "/probe." .. spec.ext
    local f = assert(io.open(path, "w"))
    f:write(spec.body)
    f:close()
    paths[ft] = path
  end
  return paths
end

---@return string[] names
local function current_clients()
  local names = {}
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
    names[#names + 1] = client.name
  end
  table.sort(names)
  return names
end

--- Probe one fixture type: open it, then poll until every expected client
--- has attached or the deadline expires.
---@param ft string
---@param path string
---@param done fun()
local function probe_type(ft, path, done)
  vim.cmd("edit " .. vim.fn.fnameescape(path))
  local expect = fixtures[ft].expect
  local elapsed = 0
  local step = 2500
  local deadline = 45000

  local function poll()
    elapsed = elapsed + step
    local names = current_clients()
    local all = true
    for _, want in ipairs(expect) do
      if not vim.tbl_contains(names, want) then
        all = false
      end
    end
    if all or elapsed >= deadline then
      emit(
        string.format("PROBE_CLIENTS %s ft=%s clients=%s waited=%dms", ft, vim.bo.filetype, vim.inspect(names), elapsed)
      )
      for _, want in ipairs(expect) do
        emit(string.format("PROBE_EXPECT %s %s present=%s", ft, want, tostring(vim.tbl_contains(names, want))))
      end
      done()
      return
    end
    vim.defer_fn(poll, step)
  end
  vim.defer_fn(poll, step)
end

--- Run the fixture types in a fixed order, so the output is comparable
--- between runs and between branches.
---@param types string[]
---@param paths table<string, string>
---@param done fun()
local function probe_all(types, paths, done)
  local index = 0
  local function next()
    index = index + 1
    if index > #types then
      done()
      return
    end
    local ft = types[index]
    probe_type(ft, paths[ft], next)
  end
  next()
end

--- Stop every LSP client and wait for them to detach before quitting.
---
--- Neovim exiting does not wait for the server processes. A server such as
--- jdtls keeps running as a separate JVM and keeps writing its workspace
--- files into the sandbox after Neovim is gone, which recreates directories
--- that the cleanup has already removed. Shutting the clients down first
--- lets the servers finish while Neovim is still alive.
---@param done fun()
local function shutdown_clients(done)
  local clients = vim.lsp.get_clients()
  for _, client in ipairs(clients) do
    pcall(function()
      client.stop(true)
    end)
  end
  local waited = 0
  local step = 250
  local deadline = 5000
  local function poll()
    waited = waited + step
    if #vim.lsp.get_clients() == 0 or waited >= deadline then
      done()
      return
    end
    vim.defer_fn(poll, step)
  end
  vim.defer_fn(poll, step)
end

local scratch = vim.fn.tempname()
vim.fn.mkdir(scratch, "p")
local paths = write_fixtures(scratch)

local order = {
  "python",
  "java",
  "go",
  "typescript",
  "yaml",
  "json",
  "tex",
  "toml",
  "markdown",
  "bash",
  "dockerfile",
  "lua",
}

-- Stage 1: the plugin table, after lazy.nvim has loaded. Then probe every
-- fixture type in a fixed order.
vim.defer_fn(function()
  report_servers("loaded")
  probe_all(order, paths, function()
    -- Final: the server table again, then stop the servers and exit.
    report_servers("final")
    shutdown_clients(function()
      vim.cmd("qa!")
    end)
  end)
end, 4000)
