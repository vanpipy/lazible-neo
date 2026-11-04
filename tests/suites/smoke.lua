---@module "mini.test"

-- Smoke test: does the child actually load the repo config, and are the
-- <leader>r* mappings installed?
--
-- This test exists to catch the failure mode where the harness silently
-- loads a *different* configuration (e.g. the live ~/.config/nvim) and
-- therefore validates the wrong thing.

local child = MiniTest.new_child_neovim()

local eq = MiniTest.expect.equality

local REPO = os.getenv("RF_REPO")
if not REPO then
  error("RF_REPO is not set. Run the suite through tests/run.sh.")
end

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      -- The init file is given as an absolute path. The child's cwd is the
      -- parent's cwd (the repo root), not tests/, so a relative path would
      -- not resolve.
      child.restart({ "-u", REPO .. "/tests/harness_init.lua" })
    end,
    post_once = child.stop,
  },
})

T["smoke"] = MiniTest.new_set()

T["smoke"]["repo config is the one under test"] = function()
  -- stdpath("config") must resolve to the sandbox that points at the repo.
  local config = child.lua_get([[vim.fn.stdpath("config")]])
  print("CONFIG: " .. config)

  -- The config module must be found inside the repo, and the repo's copy must
  -- win over any live clone on the runtimepath.
  --
  -- The harness reaches the repo through a symlink at
  -- $XDG_CONFIG_HOME/nvim. The runtimepath therefore reports the *symlink*
  -- path, not the repo path, so compare the resolved paths.
  local sources = child.lua_get([[
    vim.api.nvim_get_runtime_file("lua/config/lazy.lua", false)
  ]])
  for _, s in ipairs(sources) do
    print("SOURCE: " .. s)
  end

  local resolved = child.lua_get([[
    vim.uv.fs_realpath(vim.api.nvim_get_runtime_file("lua/config/lazy.lua", false)[1])
  ]])
  print("RESOLVED: " .. resolved)
  -- The first hit on the runtimepath is the one that wins.
  eq(resolved, REPO .. "/lua/config/lazy.lua")
  -- And the repo's lazyvim.json is the one LazyVim reads.
  local json_path = child.lua_get([[
    require("lazyvim.config").json.path
  ]])
  print("JSON: " .. json_path)
  eq(json_path, config .. "/lazyvim.json")
end

T["smoke"]["repo config loaded"] = function()
  local leader = child.lua_get("vim.g.mapleader")
  eq(leader, ";")

  local has_refactoring = child.lua_get([[
    (function()
      local ok = pcall(require, "refactoring")
      return ok
    end)()
  ]])
  eq(has_refactoring, true)
end

T["smoke"]["refactor mappings present"] = function()
  local maps = child.lua_get([[
    (function()
      local leader = vim.g.mapleader
      local found = {}
      for _, mode in ipairs({ "n", "x" }) do
        for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
          if m.lhs and m.lhs:find(leader .. "r", 1, true) then
            found[#found + 1] = ("mode=%s lhs=%s desc=%s expr=%s remap=%s"):format(
              mode,
              m.lhs,
              tostring(m.desc),
              tostring(m.expr),
              tostring(m.remap)
            )
          end
        end
      end
      return found
    end)()
  ]])
  for _, line in ipairs(maps) do
    print("MAP: " .. line)
  end
  eq(#maps > 0, true)
end

return T
