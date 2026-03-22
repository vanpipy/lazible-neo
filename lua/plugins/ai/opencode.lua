return {
  "nickjvandyke/opencode.nvim",
  version = "*",
  lazy = true,
  dependencies = {
    {
      "folke/snacks.nvim",
      optional = true,
      opts = {
        input = {},
        picker = {
          actions = {
            opencode_send = function(...)
              return require("opencode").snacks_picker_send(...)
            end,
          },
          win = {
            input = {
              keys = {
                ["<a-a>"] = {
                  "opencode_send",
                  mode = { "n", "i" },
                },
              },
            },
          },
        },
      },
    },
  },
  init = function()
    local preferred_port = tonumber(vim.env.OPENCODE_PORT) or 4189
    local port_pinned = vim.env.OPENCODE_PORT ~= nil and vim.env.OPENCODE_PORT ~= ""
    local current_port = preferred_port
    local session = {
      cmd = nil,
      opts = nil,
      cwd = nil,
      model = nil,
      started_by_us = false,
    }

    local function root_dir()
      local buf = vim.api.nvim_get_current_buf()
      local name = vim.api.nvim_buf_get_name(buf)
      if type(name) == "string" and name ~= "" then
        local dir = vim.fs.dirname(name)
        local root = vim.fs.root(dir, { ".git", "opencode.json" })
        if type(root) == "string" and root ~= "" then
          return root
        end
      end
      
      local ok_lv, lv = pcall(function()
        return LazyVim
      end)
      if ok_lv and lv and type(lv.root) == "function" then
        local r = lv.root({ buf = 0, normalize = true })
        if type(r) == "string" and r ~= "" then
          return r
        end
      end
      return vim.fn.getcwd()
    end

    local function is_port_in_use(p)
      if vim.fn.executable("lsof") ~= 1 then
        return false
      end
      local pids = vim.fn.systemlist({ "lsof", "-nP", "-iTCP:" .. tostring(p), "-sTCP:LISTEN", "-t" })
      return type(pids) == "table" and #pids > 0
    end

    local function pick_free_port()
      local uv = vim.uv or vim.loop
      if not uv or type(uv.new_tcp) ~= "function" then
        return nil
      end
      local tcp = uv.new_tcp()
      if not tcp then
        return nil
      end
      local ok = pcall(function()
        tcp:bind("127.0.0.1", 0)
      end)
      if not ok then
        tcp:close()
        return nil
      end
      local sock = tcp:getsockname()
      tcp:close()
      if type(sock) == "table" and type(sock.port) == "number" then
        return sock.port
      end
      return nil
    end

    local function ensure_port()
      if not is_port_in_use(current_port) then
        return current_port
      end
      if port_pinned then
        vim.notify(("opencode port %d is already in use (OPENCODE_PORT is pinned)"):format(current_port), vim.log.levels.WARN)
        return nil
      end
      local p = pick_free_port()
      if type(p) == "number" then
        current_port = p
      end
      return current_port
    end

    local function build_cmd(model)
      local port = ensure_port()
      if not port then
        return nil
      end
      local cmd = ("opencode --port %d"):format(port)
      if vim.env.OPENCODE_HOSTNAME and vim.env.OPENCODE_HOSTNAME ~= "" then
        cmd = ("%s --hostname %s"):format(cmd, vim.env.OPENCODE_HOSTNAME)
      end
      if model and model ~= "" then
        cmd = ("%s --model %s"):format(cmd, model)
      end
      if vim.env.OPENCODE_PRINT_LOGS == "1" then
        local level = vim.env.OPENCODE_LOG_LEVEL or "INFO"
        cmd = ("%s --print-logs --log-level %s"):format(cmd, level)
      end
      return cmd
    end
    
    -- 终端配置
    vim.g.opencode_snacks_terminal_opts = {
      win = {
        position = "right",
        enter = true,
        on_win = function(win)
          require("opencode.terminal").setup(win.win)
        end,
      },
    }
    
    local function ensure_session(model)
      if session.cmd and session.opts then
        return true
      end
      if not session.cwd then
        session.cwd = root_dir()
      end
      if session.model == nil then
        session.model = model or (vim.env.OPENCODE_MODEL_DEFAULT or "")
      else
        session.model = model or session.model
      end
      local cmd = build_cmd(session.model)
      if not cmd then
        return false
      end
      session.cmd = cmd
      session.opts = vim.tbl_deep_extend("force", vim.g.opencode_snacks_terminal_opts, { cwd = session.cwd })
      return true
    end

    local function get_term(snacks_terminal)
      if not session.cmd or not session.opts then
        return nil
      end
      return snacks_terminal.get(session.cmd, session.opts)
    end

    local function kill_opencode_by_port(p)
      if not session.started_by_us then
        return
      end
      if vim.fn.executable("lsof") ~= 1 or vim.fn.executable("ps") ~= 1 or vim.fn.executable("kill") ~= 1 then
        return
      end
      local pids = vim.fn.systemlist({ "lsof", "-nP", "-iTCP:" .. tostring(p), "-sTCP:LISTEN", "-t" })
      if type(pids) ~= "table" or #pids == 0 then
        return
      end
      for _, pid in ipairs(pids) do
        if type(pid) == "string" and pid ~= "" then
          local args = vim.fn.systemlist({ "ps", "-p", pid, "-o", "args=" })
          local line = type(args) == "table" and args[1] or ""
          if type(line) == "string" and line:match("opencode") then
            pcall(vim.fn.system, { "kill", "-TERM", pid })
          end
        end
      end
      for _, pid in ipairs(pids) do
        if type(pid) == "string" and pid ~= "" then
          local args = vim.fn.systemlist({ "ps", "-p", pid, "-o", "args=" })
          local line = type(args) == "table" and args[1] or ""
          if type(line) == "string" and line:match("opencode") then
            pcall(vim.fn.system, { "kill", "-KILL", pid })
          end
        end
      end
    end
    
    -- 重启函数
    vim.g.opencode_restart_with_model = function(model)
      local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
      if not ok_term then
        vim.notify("snacks.nvim not available", vim.log.levels.ERROR)
        return
      end
      
      local term = get_term(snacks_terminal)
      if term then
        term:close()
      end
      
      kill_opencode_by_port(current_port)

      session.cmd = nil
      session.opts = nil
      session.cwd = nil
      session.model = model or ""
      session.started_by_us = false

      if not ensure_session(session.model) then
        return
      end
      if vim.g.opencode_opts then
        vim.g.opencode_opts.port = current_port
      end

      local success, err = pcall(function()
        snacks_terminal.open(session.cmd, session.opts)
      end)
      
      if not success then
        vim.notify("Failed to start opencode: " .. tostring(err), vim.log.levels.ERROR)
      else
        session.started_by_us = true
      end
    end
    
    -- 配置 opencode 插件
    vim.g.opencode_model_default = vim.env.OPENCODE_MODEL_DEFAULT or ""
    vim.g.opencode_model_deepseek = vim.env.OPENCODE_MODEL_DEEPSEEK or "deepseek/deepseek-chat"

    vim.g.opencode_opts = {
      port = current_port,
      lsp = { enabled = true },
      server = {
        start = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            vim.notify("snacks.nvim not available", vim.log.levels.ERROR)
            return
          end
          if not ensure_session(session.model) then
            return
          end
          vim.g.opencode_opts.port = current_port
          snacks_terminal.open(session.cmd, session.opts)
          session.started_by_us = true
        end,
        stop = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            return
          end
          local term = get_term(snacks_terminal)
          if term then
            term:close()
          end
          kill_opencode_by_port(current_port)
          session.cmd = nil
          session.opts = nil
          session.cwd = nil
          session.started_by_us = false
        end,
        toggle = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            return
          end
          if not ensure_session(session.model) then
            return
          end
          local existed = get_term(snacks_terminal) ~= nil
          vim.g.opencode_opts.port = current_port
          snacks_terminal.toggle(session.cmd, session.opts)
          if not existed then
            session.started_by_us = true
          end
        end,
      },
    }
  end,
  config = function()
    vim.o.autoread = true
    
    -- 安全包装 ask 函数
    local ok_ctx, ctx = pcall(require, "opencode.context")
    if ok_ctx and type(ctx.render) == "function" then
      local orig = ctx.render
      ctx.render = function(self, prompt, agents, ...)
        if prompt == nil then
          prompt = ""
        end
        return orig(self, prompt, agents, ...)
      end
    end
    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        if vim.g.opencode_opts and vim.g.opencode_opts.server and type(vim.g.opencode_opts.server.stop) == "function" then
          pcall(vim.g.opencode_opts.server.stop)
        end
      end,
    })
  end,
  keys = {
    { "<leader>o", group = "opencode" },
    { "<leader>oa", function() require("opencode").ask("@this: ", { submit = true }) end, 
      desc = "Opencode Ask", mode = { "n", "v" } },
    { "<leader>oo", function() require("opencode").toggle() end, desc = "Opencode Toggle" },
    { "<leader>os", function() require("opencode").select() end, desc = "Opencode Select" },
    { "<leader>op", function() require("opencode").select() end, desc = "Opencode Prompt" },
    { "<leader>oh", "<cmd>checkhealth opencode<cr>", desc = "Opencode Health" },
    { "<leader>oM", function() require("opencode").ask("/models", { submit = true }) end, 
      desc = "Opencode Models" },
    { "<leader>oC", function() require("opencode").ask("/connect", { submit = true }) end, 
      desc = "Opencode Connect" },
    { "<leader>oD", function() 
      vim.g.opencode_restart_with_model(vim.g.opencode_model_deepseek) 
    end, desc = "Opencode Model: DeepSeek" },
    { "<leader>o0", function() 
      vim.g.opencode_restart_with_model(vim.g.opencode_model_default) 
    end, desc = "Opencode Model: Default" },
    { "<leader>or", function() 
      vim.g.opencode_restart_with_model(nil) 
    end, desc = "Opencode Restart" },
  },
}
