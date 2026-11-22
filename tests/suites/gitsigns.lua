---@module "mini.test"

-- Runtime validation of the <leader>h* gitsigns mappings that
-- lua/plugins/editing/gitsigns.lua installs.
--
-- The child Neovim loads the real repo config, so the mappings under test are
-- the ones the user actually gets. The repo's mapleader is ";", so each
-- sequence starts with ";".
--
-- What is asserted here:
--   * every advertised <leader>h* mapping exists, in the right mode
--   * each mapping carries the description it advertises
--   * pressing a mapping does not raise
--   * <leader>hs really stages a hunk, against a real git repository
--   * LazyVim's own <leader>gh* mappings still exist alongside them
--   * LazyVim's gitsigns options (the sign glyph, the on_attach callback)
--     survive the second plugin spec
--   * the inline blame annotation is on by default, follows the cursor and
--     can be toggled off and on again
--
-- The upstream snippet this file is based on called a GLOBAL `gitsigns`
-- table. Upstream gitsigns no longer creates one, so a global reference
-- raises "attempt to call a nil value" the first time it is pressed. The
-- mappings here require the module explicitly, and the "pressing does not
-- raise" assertion is what catches a regression back to a global reference.
--
-- Note on the shape of the child calls: mini.test's RPC channel cannot carry
-- a Lua table that contains a function, and `nvim_get_keymap` reports the
-- callback of a Lua mapping as a function. So every lookup happens INSIDE
-- the child, and only plain strings and booleans come back out.

local child = MiniTest.new_child_neovim()

local eq = MiniTest.expect.equality

local REPO = os.getenv("RF_REPO") or vim.fn.getcwd()

-- The mappings lua/plugins/editing/gitsigns.lua is expected to install.
--
-- `mode` is the mode the mapping must exist in. The visual-mode stage/reset
-- mappings are separate entries from the normal-mode ones, because gitsigns
-- needs the selected range and the range only exists in Visual mode.
local EXPECTED = {
  { lhs = "hs", mode = "n", desc = "Gitsigns Stage Hunk" },
  { lhs = "hr", mode = "n", desc = "Gitsigns Reset Hunk" },
  { lhs = "hs", mode = "v", desc = "Gitsigns Stage Hunk" },
  { lhs = "hr", mode = "v", desc = "Gitsigns Reset Hunk" },
  { lhs = "hS", mode = "n", desc = "Gitsigns Stage Buffer" },
  { lhs = "hR", mode = "n", desc = "Gitsigns Reset Buffer" },
  { lhs = "hp", mode = "n", desc = "Gitsigns Preview Hunk" },
  { lhs = "hi", mode = "n", desc = "Gitsigns Preview Hunk Inline" },
  { lhs = "hb", mode = "n", desc = "Gitsigns Blame Line" },
  { lhs = "hB", mode = "n", desc = "Gitsigns Toggle Current Line Blame" },
  { lhs = "hd", mode = "n", desc = "Gitsigns Diff This" },
  { lhs = "hD", mode = "n", desc = "Gitsigns Diff This ~" },
  { lhs = "hQ", mode = "n", desc = "Gitsigns Hunks (All Repos)" },
  { lhs = "hq", mode = "n", desc = "Gitsigns Hunks (Buffer)" },
}

---@type {[string]: any|{[string]: any}}
local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- The init file is given as an absolute path. The child's cwd is the
      -- parent's cwd (the repo root), not tests/, so a relative path would
      -- not resolve.
      child.restart({ "-u", REPO .. "/tests/harness_init.lua" })
      child.bo.readonly = false
      -- Surface errors raised inside a mapping as test failures.
      child.lua("vim.notify = function(msg, level) if level == vim.log.levels.ERROR then error(msg) end end")
    end,
    post_once = child.stop,
  },
})

--- Look up one mapping inside the child and report it as plain data.
---
--- Returns "<lhs>|<desc>" for the mapping, or nil when it does not exist.
---@param mode string
---@param lhs string
---@return string|nil
local function find_map(mode, lhs)
  return child.lua(
    [[
      local mode, lhs = ...
      for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
        if m.lhs == lhs then
          return m.lhs .. "|" .. tostring(m.desc)
        end
      end
      return nil
    ]],
    { mode, lhs }
  )
end

--- Press a key sequence the way a user types it, then let the queue drain.
---
--- `child.type_keys` goes through `nvim_input`, so the keys reach the mapping
--- exactly as a typed keypress does. `:normal!` bypasses mappings entirely,
--- and even `:normal` does not drain lazy.nvim's stub, which re-feeds the
--- keys through `nvim_feedkeys`.
---@param keys string
local function press(keys)
  child.type_keys(keys)
  -- Drain whatever the stub queued, then let gitsigns' async action finish.
  child.lua([[
    vim.api.nvim_feedkeys("", "x", false)
    vim.wait(3000)
  ]])
end

T["gitsigns"] = MiniTest.new_set()

T["gitsigns"]["all advertised mappings exist"] = function()
  local leader = child.lua_get("vim.g.mapleader")

  local missing = {}
  for _, want in ipairs(EXPECTED) do
    local lhs = leader .. want.lhs
    if not find_map(want.mode, lhs) then
      missing[#missing + 1] = ("%s (%s)"):format(lhs, want.mode)
    end
  end

  eq(#missing, 0)
end

T["gitsigns"]["mappings carry the expected description"] = function()
  local leader = child.lua_get("vim.g.mapleader")

  for _, want in ipairs(EXPECTED) do
    local lhs = leader .. want.lhs
    local found = find_map(want.mode, lhs)
    -- Guard against a nil dereference below when the mapping is missing, so
    -- the failure message names the mapping rather than the index.
    if not found then
      error(("mapping %s (%s) is missing"):format(lhs, want.mode))
    end
    eq(found, lhs .. "|" .. want.desc)
  end
end

T["gitsigns"]["pressing a mapping does not raise"] = function()
  -- Press every normal-mode mapping. The actions are safe to invoke in a
  -- git-backed buffer with no hunks: gitsigns' actions return early when
  -- there is nothing to act on.
  local leader = child.lua_get("vim.g.mapleader")

  local failures = {}
  for _, want in ipairs(EXPECTED) do
    if want.mode == "n" then
      local ok, err = pcall(child.type_keys, leader .. want.lhs)
      if not ok then
        failures[#failures + 1] = ("%s: %s"):format(want.lhs, tostring(err))
      end
      -- Drain the key queue between presses, so one press cannot bleed into
      -- the next one.
      child.lua([[vim.wait(300)]])
    end
  end

  eq(#failures, 0)
end

T["gitsigns"]["the plugin loads on demand"] = function()
  -- gitsigns is a `LazyFile` plugin in LazyVim, so in a child that has not
  -- opened a file yet it is not loaded.
  local before = child.lua([[
    local plugin = require("lazy.core.config").plugins["gitsigns.nvim"]
    return plugin ~= nil and plugin._.loaded ~= nil
  ]])
  eq(before, false)

  -- Pressing one of the new mappings loads it, through lazy.nvim's key
  -- stub. That is what makes the shortcuts work in a buffer that gitsigns
  -- has not attached to yet.
  press(child.lua_get("vim.g.mapleader") .. "hs")

  local after = child.lua([[
    local plugin = require("lazy.core.config").plugins["gitsigns.nvim"]
    return plugin ~= nil and plugin._.loaded ~= nil
  ]])
  eq(after, true)
end

T["gitsigns"]["the new mappings are global"] = function()
  -- The new mappings are installed by lazy.nvim's `keys` field, so they are
  -- global. They are therefore live in every buffer, including buffers
  -- gitsigns has not attached to. That is the difference from LazyVim's own
  -- `<leader>gh*` mappings, which are buffer-local.
  --
  -- The child has not opened a file at this point, so there is no attached
  -- buffer at all.
  local found = child.lua([[
    local leader = vim.g.mapleader
    local out = {}
    for _, m in ipairs(vim.api.nvim_get_keymap("n")) do
      if m.lhs and m.lhs:find(leader .. "h", 1, true) and not m.lhs:find(leader .. "gh", 1, true) then
        out[#out + 1] = m.lhs
      end
    end
    return out
  ]])

  eq(#found, 12)
end

T["gitsigns"]["LazyVim's own gitsigns mappings survive"] = function()
  -- The new spec is a second fragment for the same plugin. LazyVim's
  -- `on_attach` mappings must still be installed, otherwise adding these
  -- shortcuts would silently break the `<leader>gh*` family.
  --
  -- Those mappings are BUFFER-LOCAL: LazyVim installs them from gitsigns'
  -- `on_attach` callback with `{ buffer = buffer }`. `nvim_get_keymap` only
  -- reports global mappings, so the buffer-local list has to be read
  -- instead. That also means a git-backed buffer has to be open first.
  local leader = child.lua_get("vim.g.mapleader")

  child.lua(
    [[
      local repo = ...
      vim.cmd("edit " .. vim.fn.fnameescape(repo .. "/README.md"))
      vim.wait(10000, function()
        return require("gitsigns.cache").cache[vim.api.nvim_get_current_buf()] ~= nil
      end)
      vim.wait(2000)
    ]],
    { REPO }
  )

  local found = child.lua(
    [[
      local leader = ...
      local bufnr = vim.api.nvim_get_current_buf()
      local out = {}
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if m.lhs and m.lhs:find(leader .. "gh", 1, true) then
          out[#out + 1] = m.lhs
        end
      end
      return out
    ]],
    { leader }
  )

  -- LazyVim binds <leader>ghs, ghr, ghS, ghu, ghR, ghp, ghb, ghB, ghd, ghD.
  eq(#found, 10)
end

T["gitsigns"]["gitsigns options are preserved"] = function()
  -- The merged spec must keep LazyVim's options (the sign glyphs and the
  -- `on_attach` callback). A second fragment that replaced them would turn
  -- off the sign column.
  local opts = child.lua([[
    local plugin = require("lazy.core.config").plugins["gitsigns.nvim"]
    local cfg = require("lazy.core.plugin").values(plugin, "opts", false)
    if type(cfg) ~= "table" then
      return { "not-a-table" }
    end
    return {
      tostring(type(cfg.on_attach)),
      tostring(cfg.signs and cfg.signs.add and cfg.signs.add.text),
    }
  ]])

  eq(opts[1], "function")
  eq(opts[2], "▎")
end

--- Create a throwaway git repository with one committed file, open it, and
--- wait for gitsigns to attach.
---@param repo string
---@param contents string
local function setup_git_repo(repo, contents)
  child.lua(
    [[
      local repo, contents = ...
      vim.fn.delete(repo, "rf")
      vim.fn.mkdir(repo, "p")
      vim.fn.system(("cd %s && git init -q && git config user.email t@t.t && git config user.name t"):format(repo))
      vim.fn.system(("cd %s && printf %s > f.txt && git add f.txt && git commit -qm init"):format(repo, contents))
      vim.cmd("cd " .. vim.fn.fnameescape(repo))
      vim.cmd("edit " .. vim.fn.fnameescape(repo .. "/f.txt"))
    ]],
    { repo, contents }
  )

  -- Wait for gitsigns to attach to the new buffer.
  child.lua([[
    vim.wait(10000, function()
      return require("gitsigns.cache").cache[vim.api.nvim_get_current_buf()] ~= nil
    end)
    vim.wait(2000)
  ]])
end

--- Read the staged diff of a repository.
---@param repo string
---@return string
local function staged_diff(repo)
  return child.lua(
    [[
      local repo = ...
      return vim.fn.system(("cd %s && git diff --cached"):format(repo))
    ]],
    { repo }
  )
end

--- Create a git repository whose file has two authors, and open it.
---
--- The file has three lines:
---   * line 1 and line 3 were written by the first commit ("Alice")
---   * line 2 was changed by the second commit ("Bob")
---
--- The repository's `user.name` is "Alice", so gitsigns renders Alice's lines as
--- "You" (its `self_author_text`). Bob's line is rendered as "Bob". The two
--- are therefore distinguishable, which is what the cursor-following assertion
--- needs.
---@param repo string
local function setup_two_author_repo(repo)
  child.lua(
    [[
      local repo = ...
      vim.fn.delete(repo, "rf")
      vim.fn.mkdir(repo, "p")
      vim.fn.system(("cd %s && git init -q && git config user.email alice@example.com && git config user.name Alice"):format(repo))
      vim.fn.system(("cd %s && printf 'one\\ntwo\\nthree\\n' > f.txt && git add f.txt && git commit -qm 'first commit'"):format(repo))
      vim.fn.system(("cd %s && printf 'one\\nTWO\\nthree\\n' > f.txt && git add f.txt && git commit -qm 'second commit' --author='Bob <bob@example.com>'"):format(repo))
      vim.cmd("cd " .. vim.fn.fnameescape(repo))
      vim.cmd("edit " .. vim.fn.fnameescape(repo .. "/f.txt"))
    ]],
    { repo }
  )

  -- Wait for gitsigns to attach to the new buffer.
  child.lua([[
    vim.wait(10000, function()
      return require("gitsigns.cache").cache[vim.api.nvim_get_current_buf()] ~= nil
    end)
 ]])
end

--- Read the inline blame annotation of the current buffer.
---
--- gitsigns stores the rendered annotation in `b:gitsigns_blame_line` and the
--- raw blame data in `b:gitsigns_blame_line_dict`. The rendered string is what
--- the user actually sees, so that is what the assertion uses.
---
--- An unset buffer variable comes back as `vim.NIL`, which is userdata and
--- would break the `string.find` below. It is normalised to nil here, so a
--- missing annotation fails with a clear message.
---@return string|nil
local function current_line_blame()
  local blame = child.lua([[
    return vim.b.gitsigns_blame_line
  ]])

  if type(blame) ~= "string" then
    return nil
  end
  return blame
end

--- Move the cursor one line down, the way a user does, and let the
--- annotation catch up.
---
--- The cursor has to be moved with real input. `nvim_win_set_cursor` does not
--- fire CursorMoved, and CursorMoved is what drives the annotation: gitsigns
--- resets the annotation and recomputes it there.
local function cursor_down()
  child.type_keys("j")
  -- The annotation is refreshed on a timer (gitsigns' `delay` option), so the
  -- wait has to outlast it.
  child.lua([[vim.wait(3000)]])
end

T["gitsigns"]["the inline blame annotation is on by default"] = function()
  -- The whole point of the inline blame: the author of the line under the
  -- cursor is visible without pressing anything.
  --
  -- The option is read from the merged plugin opts, which is what decides
  -- whether gitsigns attaches the annotation at all.
  local opts = child.lua([[
    local plugin = require("lazy.core.config").plugins["gitsigns.nvim"]
    local cfg = require("lazy.core.plugin").values(plugin, "opts", false)
    return {
      tostring(cfg.current_line_blame),
      tostring(cfg.current_line_blame_formatter),
    }
  ]])

  eq(opts[1], "true")
  -- The compact formatter: the author and the relative time, without the
  -- commit summary, which is long enough to push the annotation off screen.
  eq(opts[2], " <author>, <author_time:%R> ")
end

T["gitsigns"]["the inline blame annotation shows the author of the current line"] = function()
  local repo = REPO .. "/tests/.deps/work/gitsigns_blame"

  setup_two_author_repo(repo)

  -- Wait for the annotation to be computed for the line the cursor opened on.
  child.lua([[vim.wait(3000)]])

  local blame = current_line_blame()
  if not blame then
    error("the inline blame annotation was not set")
  end
  -- Line 1 belongs to Alice, who is this repository's `user.name`, so
  -- gitsigns renders it as "You".
  eq(blame:find("You", 1, true) ~= nil, true)
end

T["gitsigns"]["the inline blame annotation follows the cursor"] = function()
  local repo = REPO .. "/tests/.deps/work/gitsigns_blame_follow"

  setup_two_author_repo(repo)
  child.lua([[vim.wait(3000)]])

  -- The cursor starts on line 1, which is Alice's line.
  local first = current_line_blame()
  if not first then
    error("the inline blame annotation was not set")
  end
  eq(first:find("You", 1, true) ~= nil, true)

  -- Line 2 was changed by Bob, so moving down must change the annotation.
  cursor_down()

  local blame = current_line_blame()
  if not blame then
    error("the inline blame annotation was cleared instead of updated")
  end
  eq(blame:find("Bob", 1, true) ~= nil, true)
end

T["gitsigns"]["the toggle switches the inline blame off and on again"] = function()
  local repo = REPO .. "/tests/.deps/work/gitsigns_blame_toggle"

  setup_two_author_repo(repo)
  child.lua([[vim.wait(3000)]])

  local leader = child.lua_get("vim.g.mapleader")

  -- Switching it off: gitsigns removes the annotation.
  press(leader .. "hB")
  child.lua([[vim.wait(3000)]])

  eq(child.lua([[return require("gitsigns.config").config.current_line_blame]]), false)

  -- Switching it back on: gitsigns re-runs its setup, which restores the
  -- annotation on the next update.
  press(leader .. "hB")
  child.lua([[vim.wait(3000)]])

  eq(child.lua([[return require("gitsigns.config").config.current_line_blame]]), true)
end

T["gitsigns"]["staging a hunk works end to end"] = function()
  -- The real check. A throwaway git repository is created, a file is
  -- committed and then edited, and `<leader>hs` is pressed. The staged diff
  -- must contain the change.
  --
  -- The cursor has to sit on the changed line: gitsigns' `stage_hunk` with
  -- no argument stages the hunk AT THE CURSOR.
  local repo = REPO .. "/tests/.deps/work/gitsigns_e2e"

  setup_git_repo(repo, "'line one\\nline two\\nline three\\n'")

  -- Edit line 2 and put the cursor on it.
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "line TWO" })
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.wait(2000)
  ]])

  eq(vim.trim(staged_diff(repo)), "")

  press(child.lua_get("vim.g.mapleader") .. "hs")

  eq(staged_diff(repo):find("+line TWO", 1, true) ~= nil, true)
end

T["gitsigns"]["staging a visual range works end to end"] = function()
  -- The visual-mode mapping passes an explicit range to gitsigns, built from
  -- `vim.fn.line('.')` and `vim.fn.line('v')`. The selection here is
  -- BACKWARDS (the cursor ends up above the mark), which is the case that
  -- catches a range built in the wrong order.
  --
  -- The selection spans lines 2 to 4 while the hunk is on line 3, so the
  -- range has to reach the hunk.
  local repo = REPO .. "/tests/.deps/work/gitsigns_visual"

  setup_git_repo(repo, "'a\\nb\\nc\\nd\\ne\\n'")

  -- Change line 3 only.
  child.lua([[
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 2, 3, false, { "C" })
    vim.wait(2000)
  ]])

  -- Enter visual mode on line 4 and extend the selection up to line 2.
  child.lua([[
    vim.api.nvim_win_set_cursor(0, { 4, 0 })
    vim.cmd("normal! v")
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.wait(1000)
  ]])

  press(child.lua_get("vim.g.mapleader") .. "hs")

  local diff = staged_diff(repo)
  eq(diff:find("+C", 1, true) ~= nil, true)
  -- Only the changed line is staged, not the whole selection.
  eq(diff:find("-b", 1, true), nil)
  eq(diff:find("-d", 1, true), nil)
end

return T
