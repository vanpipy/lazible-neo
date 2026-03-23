local M = {}

function M.check()
  local health = vim.health or require("health")

  health.start("opencode")

  if vim.fn.executable("opencode") == 1 then
    health.ok("opencode CLI is available")
  else
    health.error("opencode CLI is not found in PATH", {
      "Install opencode and make sure `opencode` is in PATH",
      "Verify with: opencode --version",
    })
  end

  if vim.g.opencode_opts ~= nil then
    health.ok("vim.g.opencode_opts is set")
  else
    health.warn("vim.g.opencode_opts is not set (plugin may not be initialized yet)", {
      "Check that the opencode.nvim plugin is loaded",
      "Try triggering it with your keymap: <leader>oo",
    })
  end

  local ok_term = pcall(require, "snacks.terminal")
  if ok_term then
    health.ok("snacks.nvim is available (optional picker integration)")
  else
    health.warn("snacks.nvim is not available (optional picker integration disabled)", {
      "Ensure folke/snacks.nvim is installed and enabled",
    })
  end

  local port = tonumber(vim.env.OPENCODE_PORT) or (vim.g.opencode_opts and vim.g.opencode_opts.port) or 4189
  if health.info then
    health.info(("port: %s"):format(tostring(port)))
  end
  if health.info then
    health.info(("nvim_manage_server: %s"):format(tostring(vim.g.opencode_nvim_manage_server == true)))
  end

  local global_cfg = vim.fn.expand("~/.config/opencode/opencode.json")
  if vim.fn.filereadable(global_cfg) == 1 then
    health.ok(("global config found: %s"):format(global_cfg))
  else
    health.warn(("global config not found: %s"):format(global_cfg))
  end

  if vim.fn.executable("lsof") == 1 then
    local pids = vim.fn.systemlist({ "lsof", "-nP", "-iTCP:" .. tostring(port), "-sTCP:LISTEN", "-t" })
    if type(pids) == "table" and #pids > 0 then
      local opencode_pid = nil
      if vim.fn.executable("ps") == 1 then
        for _, pid in ipairs(pids) do
          local args = vim.fn.systemlist({ "ps", "-p", pid, "-o", "args=" })
          local line = type(args) == "table" and args[1] or ""
          if type(line) == "string" and line:match("opencode") then
            opencode_pid = pid
            break
          end
        end
      end

      if opencode_pid then
        health.ok(("opencode server detected on port %s (pid %s)"):format(tostring(port), tostring(opencode_pid)))
      else
        health.warn(("port %s is in use, but it does not look like opencode"):format(tostring(port)))
      end
    else
      health.warn(("no opencode server detected on port %s"):format(tostring(port)), {
        ("Start it with: opencode --port %s"):format(tostring(port)),
      })
    end
  else
    health.warn("lsof not found; cannot verify whether the opencode port is in use")
  end

  local project_cfg
  if vim.fs and vim.fs.find then
    project_cfg = vim.fs.find("opencode.json", { upward = true, type = "file" })[1]
  else
    local found = vim.fn.findfile("opencode.json", ".;")
    project_cfg = found ~= "" and found or nil
  end
  if project_cfg then
    health.ok(("project config found: %s"):format(project_cfg))
  else
    health.warn("project config opencode.json not found (this is optional)")
  end
end

return M
