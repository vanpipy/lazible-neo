---@module "mini.test"

-- Runtime validation of the <leader>r* refactoring mappings that
-- lua/plugins/extras/refactoring.lua installs.
--
-- Ground truth is upstream's own fixtures (refactoring.nvim/tests/files) and
-- upstream's own public API contract (refactoring.nvim/lua/refactoring.lua and
-- refactoring.nvim/README.md). Neither the expected output nor the operator
-- semantics are invented here.
--
-- The child Neovim loads the real repo config, so the mappings under test are
-- the ones the user actually gets. The repo's mapleader is ";", so each
-- sequence starts with ";".
--
-- Operator semantics that drive the sequences below (upstream's own docs,
-- refactoring.nvim/README.md and |g@|):
--   * `g@{motion}` calls 'operatorfunc' after a motion is supplied.
--   * `inline_var()`, `inline_func()` and `print_loc()` return "g@l", which
--     already contains its motion. They act on the cursor alone.
--   * `extract_var()`, `extract_func()`, `extract_func_to_file()` and
--     `print_var()` return a bare "g@", so a motion must follow.
--   * `cleanup()` returns a bare "g@"; the repo appends "ag", mini.ai's
--     "around buffer" textobject, so it needs no motion from the user.
--
-- Upstream's own test sequences are expressed in terms of *upstream's* keymap
-- names (" ai" is their `<leader>ai` mapping). The equivalent upstream motion
-- is reused here so the fixtures stay comparable, but the repo's mapping
-- supplies the operator itself, so no trailing motion is added where the
-- repo's mapping already returns a complete sequence.

local child = MiniTest.new_child_neovim()

local eq = MiniTest.expect.equality

-- Fixtures and scratch space live next to the suite, so the harness works
-- from a fresh clone without any absolute paths.
--
-- The suite runs with the repository root as the working directory
-- (tests/run.sh cd's there), and the repo path is also passed in RF_REPO.
local REPO = os.getenv("RF_REPO") or vim.fn.getcwd()
local FIX = REPO .. "/tests/fixtures"
local WORK = REPO .. "/tests/.deps/work"

---@type {[string]: any|{[string]: any}}
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- The init file is given as an absolute path. The child's cwd is the
      -- parent's cwd (the repo root), not tests/, so a relative path would
      -- not resolve.
      child.restart({ "-u", REPO .. "/tests/harness_init.lua" })
      child.bo.readonly = false
      -- Surface upstream errors as test failures, like upstream does.
      child.lua("vim.notify = function(msg, level) if level == vim.log.levels.ERROR then error(msg) end end")
      -- Match upstream's test environment for Lua.
      child.lua([[
vim.api.nvim_create_autocmd('FileType', {
  pattern = 'lua',
  command = 'setlocal expandtab shiftwidth=2'
})
]])
    end,
    post_once = child.stop,
  },
})

---@param path string
---@return string
local function read_file(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return (s:gsub("\n$", ""))
end

---@param name string
---@return string
local function workdir(name)
  local dir = WORK .. "/" .. name
  vim.fn.delete(dir, "rf")
  vim.fn.mkdir(dir, "p")
  -- A root marker so lua_ls attaches exactly as it does upstream.
  vim.fn.mkdir(dir .. "/.git", "p")
  return dir
end

---@param name string
---@param fixture string
---@return string
local function open_fixture(name, fixture)
  local dir = workdir(name)
  local target = dir .. "/tmp.lua"
  local f = assert(io.open(target, "wb"))
  f:write(read_file(FIX .. "/" .. fixture) .. "\n")
  f:close()
  child.cmd("silent! %bwipeout!")
  child.cmd("edit " .. target)
  -- Wait for the filetype to be detected.
  child.lua([[vim.wait(5000, function() return vim.bo.filetype == 'lua' end)]])
  return target
end

---@param ms integer
local function sleep(ms)
  vim.uv.sleep(ms)
  -- Poke the child's event loop so it is up to date.
  child.api.nvim_eval("1")
end

--- Poll the child's buffer until it matches `expected`, or the timeout expires.
--
-- The refactors are asynchronous: `inline_var` and `inline_func` wait for two
-- LSP round trips (`textDocument/definition` and `textDocument/references`)
-- plus a tree-sitter pass before they apply their edits. Measured in this
-- harness that takes roughly 3.5s, well past any fixed sleep that fits a
-- test suite. Polling for the expected content removes the race instead of
-- papering over it with a longer sleep.
---@param expected string[]
---@param timeout_ms integer
---@return boolean
local function wait_for_lines(expected, timeout_ms)
  local start = vim.uv.now()
  while vim.uv.now() - start < timeout_ms do
    vim.uv.sleep(100)
    -- Poke the child's event loop so it is up to date.
    child.api.nvim_eval("1")
    if vim.deep_equal(child.api.nvim_buf_get_lines(0, 0, -1, true), expected) then
      return true
    end
  end
  return false
end

---@param name string
---@param fixture string
---@param cursor {[1]: integer, [2]: integer}
---@param expected_fixture string
---@param ... string
local function validate(name, fixture, cursor, expected_fixture, ...)
  open_fixture(name, fixture)
  child.api.nvim_win_set_cursor(0, cursor)
  -- Wait for the LSP the same way upstream's inline tests do.
  child.lua([[vim.wait(5000, function() return #vim.lsp.get_clients({ bufnr = 0 }) >= 1 end)]])
  child.type_keys(...)
  local expected = vim.split(read_file(FIX .. "/" .. expected_fixture), "\n")
  wait_for_lines(expected, 20000)
  eq(child.api.nvim_buf_get_lines(0, 0, -1, true), expected, { "buffer did not match " .. expected_fixture })
end

T["refactoring"] = MiniTest.new_set()

-- <leader>rs -> Select Refactor.
--
-- `select_refactor()` opens a `vim.ui.select` picker and then feeds the
-- chosen refactor's keys back through `vim.api.nvim_input`. A headless child
-- has no floating-ui provider, so the picker is stubbed with a deterministic
-- chooser. The stub still exercises the real path: the mapping calls
-- `select_refactor`, upstream builds the entry list, the callback resolves,
-- and the returned keys are fed back into the editor.
T["refactoring"]["rs select refactor"] = function()
  open_fixture("rs_select_refactor", "inline_var_simple_assignment_before.lua")
  child.api.nvim_win_set_cursor(0, { 1, 6 })
  child.lua([[vim.wait(10000, function() return #vim.lsp.get_clients({ bufnr = 0 }) >= 1 end)]])

  -- The stub must end in a convertible value: mini.test ships the child's
  -- return value back to the parent process.
  child.lua([[
_G.__selected = nil
_G.__selected_opts = nil
vim.ui.select = function(items, opts, on_choice)
  _G.__selected = items[1]
  _G.__selected_opts = { prompt = opts and opts.prompt }
  on_choice(items[1])
end
return true
]])

  child.type_keys(";rs")

  -- `vim.api.nvim_input` is asynchronous, and the inline refactor then waits
  -- for two LSP round trips, so poll for the expected content.
  local expected = vim.split(read_file(FIX .. "/inline_var_simple_assignment_after.lua"), "\n")
  wait_for_lines(expected, 20000)

  local picked = child.lua_func(function()
    local sel = _G.__selected
    -- Only serializable fields: the entry also carries a `fn` function
    -- reference, which cannot cross the process boundary.
    return {
      name = sel and sel.name or nil,
      command = sel and sel.command or nil,
      prompt = _G.__selected_opts and _G.__selected_opts.prompt or nil,
    }
  end)

  eq(picked.name, "Inline variable", { "picker did not offer the inline variable refactor" })
  eq(picked.command, "inline_var", { "picker selected the wrong refactor" })
  eq(picked.prompt, "Select a refactor:", { "picker prompt was not shown" })
  eq(
    child.api.nvim_buf_get_lines(0, 0, -1, true),
    expected,
    { "buffer did not match inline_var_simple_assignment_after.lua" }
  )
end

-- <leader>ri -> Inline Variable.
-- inline_var() returns "g@l", so the mapping is a complete sequence.
T["refactoring"]["ri inline variable"] = function()
  validate(
    "ri_inline_var",
    "inline_var_simple_assignment_before.lua",
    { 1, 6 },
    "inline_var_simple_assignment_after.lua",
    ";ri"
  )
end

-- <leader>rI -> Inline Function.
-- inline_func() returns "g@l", so the mapping is a complete sequence.
T["refactoring"]["rI inline function"] = function()
  validate("rI_inline_func", "inline_func_works_before.lua", { 1, 15 }, "inline_func_works_after.lua", ";rI")
end

-- <leader>rv -> Extract Variable.
-- extract_var() returns a bare "g@", so a motion must follow. Upstream's own
-- sequence for this refactor uses the motion "i)".
T["refactoring"]["rv extract variable"] = function()
  validate(
    "rv_extract_var",
    "extract_var_works_before.lua",
    { 2, 0 },
    "extract_var_works_after.lua",
    ";rv",
    "i)",
    "foo<cr>"
  )
end

-- <leader>rf -> Extract Function.
-- extract_func() returns a bare "g@". Upstream's own sequence uses "ip".
T["refactoring"]["rf extract function"] = function()
  validate(
    "rf_extract_func",
    "extract_func_works_before.lua",
    { 15, 0 },
    "extract_func_works_after.lua",
    ";rf",
    "ip",
    "bar<cr>"
  )
end

-- <leader>rF -> Extract Function To File.
-- extract_func_to_file() returns a bare "g@". Upstream's own sequence uses the
-- current-line motion "_", then the file name and the function name.
T["refactoring"]["rF extract function to file"] = function()
  local dir = workdir("rF_extract_func_to_file")
  open_fixture("rF_extract_func_to_file", "extract_func_to_new_file_before.lua")
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys(";rF", "_", "new.lua<cr>", "foo<cr>")

  local expected_source = vim.split(read_file(FIX .. "/extract_func_to_new_file_after.lua"), "\n")
  wait_for_lines(expected_source, 20000)

  eq(
    child.api.nvim_buf_get_lines(0, 0, -1, true),
    expected_source,
    { "source buffer did not match extract_func_to_new_file_after.lua" }
  )

  -- The extracted function lands in a new file.
  --
  -- Upstream creates the target with `vim.fn.bufadd` and applies the edits to
  -- that buffer. It never writes the file to disk, so the content only exists
  -- in the buffer. Switching to the same path reuses that buffer, which is
  -- what upstream's own test does. Wiping first would destroy the content.
  child.cmd("edit " .. dir .. "/new.lua")
  child.lua([[vim.wait(5000, function() return vim.bo.filetype == 'lua' end)]])
  local expected_new = vim.split(read_file(FIX .. "/extract_func_new_file.lua"), "\n")
  wait_for_lines(expected_new, 10000)
  eq(child.api.nvim_buf_get_lines(0, 0, -1, true), expected_new, { "new file did not match extract_func_new_file.lua" })
end

-- <leader>rp -> Debug Print Variable (visual mode).
-- print_var() returns a bare "g@", which acts on the visual selection.
T["refactoring"]["rp print variable below"] = function()
  validate(
    "rp_print_var",
    "print_var_works_below_before.lua",
    { 1, 0 },
    "print_var_works_below_after.lua",
    "V",
    "G",
    ";rp"
  )
end

-- <leader>rP -> Debug Print Location.
-- print_loc() returns "g@l", so the mapping is a complete sequence.
T["refactoring"]["rP print location below"] = function()
  validate("rP_print_loc", "print_loc_works_below_before.lua", { 8, 8 }, "print_loc_works_below_after.lua", ";rP")
end

-- <leader>rc -> Debug Print Cleanup.
-- cleanup() returns "g@" and the repo appends "ag", mini.ai's "around buffer"
-- textobject, so the mapping is a complete sequence over the whole buffer.
T["refactoring"]["rc cleanup"] = function()
  validate("rc_cleanup", "cleanup_works_before.lua", { 1, 0 }, "cleanup_works_after.lua", ";rc")
end

return T
