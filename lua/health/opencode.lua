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
    health.ok("snacks.terminal is available (server integration enabled)")
  else
    health.warn("snacks.terminal is not available (server integration disabled)", {
      "Ensure folke/snacks.nvim is installed and enabled",
    })
  end

  local port = tonumber(vim.env.OPENCODE_PORT) or (vim.g.opencode_opts and vim.g.opencode_opts.port) or 4189
  if health.info then
    health.info(("port: %s"):format(tostring(port)))
  end

  local project_cfg = vim.fs.find("opencode.json", { upward = true, type = "file" })[1]
  if project_cfg then
    health.ok(("project config found: %s"):format(project_cfg))
  else
    health.warn("project config opencode.json not found (this is optional)")
  end
end

return M
