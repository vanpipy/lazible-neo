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
    local port = tonumber(vim.env.OPENCODE_PORT) or 4189
    local function win_to_wsl_path(path)
      if type(path) ~= "string" or path == "" then
        return nil
      end
      local p = path:gsub("\\", "/")
      local drive, rest = p:match("^([A-Za-z]):/(.+)$")
      if not drive then
        return nil
      end
      return ("/mnt/%s/%s"):format(drive:lower(), rest)
    end

    local function should_use_wsl()
      if vim.fn.has("win32") ~= 1 then
        return false
      end
      if vim.fn.executable("opencode") == 1 then
        return false
      end
      return vim.fn.executable("wsl") == 1
    end

    local function root_dir()
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

    local function build_cmd(model)
      local use_wsl = should_use_wsl()
      local hostname = vim.env.OPENCODE_HOSTNAME or (use_wsl and "0.0.0.0" or "127.0.0.1")
      local log_level = vim.env.OPENCODE_LOG_LEVEL or "INFO"
      local log_flags = ("--print-logs --log-level %s"):format(log_level)
      local opencode_bin = vim.fn.exepath("opencode")
      if opencode_bin == "" then
        opencode_bin = "opencode"
      end
      local base
      if model and model ~= "" then
        base = ("%s --port %d --hostname %s --model %s %s"):format(opencode_bin, port, hostname, model, log_flags)
      else
        base = ("%s --port %d --hostname %s %s"):format(opencode_bin, port, hostname, log_flags)
      end

      if not use_wsl then
        return base
      end

      local distro = vim.env.OPENCODE_WSL_DISTRO
      local wsl_distro_flags = ""
      if distro and distro ~= "" then
        wsl_distro_flags = ("-d %s "):format(distro)
      end

      local wsl_cwd = win_to_wsl_path(root_dir()) or "/"
      local bash_cmd = ("cd %s && %s"):format(wsl_cwd, base)
      return ("wsl.exe %s-- bash -lc '%s'"):format(wsl_distro_flags, bash_cmd:gsub("'", "'\\''"))
    end

    vim.g.opencode_model_default = vim.env.OPENCODE_MODEL_DEFAULT
    vim.g.opencode_model_deepseek = vim.env.OPENCODE_MODEL_DEEPSEEK or "deepseek/deepseek-chat"
    vim.g.opencode_model_current = vim.g.opencode_model_default
    vim.g.opencode_cmd_current = build_cmd(vim.g.opencode_model_current)

    local function build_terminal_opts()
      local root = root_dir()
      local opts = {
        cwd = root,
        win = {
          position = "right",
          enter = true,
          on_win = function(win)
            require("opencode.terminal").setup(win.win)
          end,
        },
      }

      local env = {}
      local project_config_path = root .. "/opencode.json"
      if vim.fn.filereadable(project_config_path) == 1 then
        env.OPENCODE_CONFIG = project_config_path
        if should_use_wsl() then
          env.OPENCODE_CONFIG = win_to_wsl_path(project_config_path) or env.OPENCODE_CONFIG
        end
      end
      if not env.OPENCODE_CONFIG then
        local default_config_path = vim.fn.stdpath("config") .. "/opencode.json"
        if vim.fn.filereadable(default_config_path) == 1 then
          env.OPENCODE_CONFIG = default_config_path
          if should_use_wsl() then
            env.OPENCODE_CONFIG = win_to_wsl_path(default_config_path) or env.OPENCODE_CONFIG
          end
        end
      end
      if vim.env.DEEPSEEK_API_KEY and vim.env.DEEPSEEK_API_KEY ~= "" then
        env.DEEPSEEK_API_KEY = vim.env.DEEPSEEK_API_KEY
      end
      if next(env) ~= nil then
        opts.env = env
      end

      return opts
    end

    vim.g.opencode_snacks_terminal_opts = build_terminal_opts()

    local function refresh(model)
      vim.g.opencode_model_current = model
      vim.g.opencode_cmd_current = build_cmd(model)
      vim.g.opencode_snacks_terminal_opts = build_terminal_opts()
    end

    vim.g.opencode_restart_with_model = function(model)
      local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
      if not ok_term then
        return
      end

      local current_cmd = vim.g.opencode_cmd_current
      local opts = vim.g.opencode_snacks_terminal_opts
      local term = snacks_terminal.get(current_cmd, opts)
      if term then
        term:close()
      end

      refresh(model)
      snacks_terminal.open(vim.g.opencode_cmd_current, vim.g.opencode_snacks_terminal_opts)
    end

    vim.g.opencode_opts = {
      port = port,
      lsp = { enabled = true },
      server = {
        start = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            return
          end
          refresh(vim.g.opencode_model_current)
          snacks_terminal.open(vim.g.opencode_cmd_current, vim.g.opencode_snacks_terminal_opts)
        end,
        stop = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            return
          end
          local term = snacks_terminal.get(vim.g.opencode_cmd_current, vim.g.opencode_snacks_terminal_opts)
          if term then
            term:close()
          end
        end,
        toggle = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            return
          end
          local existing = snacks_terminal.get(vim.g.opencode_cmd_current, vim.g.opencode_snacks_terminal_opts)
          if existing then
            existing:close()
            return
          end
          refresh(vim.g.opencode_model_current)
          snacks_terminal.open(vim.g.opencode_cmd_current, vim.g.opencode_snacks_terminal_opts)
        end,
      },
    }
  end,
  config = function()
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
  end,
  keys = {
    { "<leader>o", group = "opencode" },
    { "<leader>oa", function() require("opencode").ask("@this: ", { submit = true }) end, desc = "Opencode Ask", mode = { "n", "v" } },
    { "<leader>oo", function() require("opencode").toggle() end, desc = "Opencode Toggle" },
    { "<leader>os", function() require("opencode").select() end, desc = "Opencode Select" },
    { "<leader>op", function() require("opencode").select() end, desc = "Opencode Prompt" },
    { "<leader>oh", "<cmd>checkhealth opencode<cr>", desc = "Opencode Health" },
    { "<leader>oM", function() require("opencode").ask("/models", { submit = true }) end, desc = "Opencode Models" },
    { "<leader>oC", function() require("opencode").ask("/connect", { submit = true }) end, desc = "Opencode Connect" },
    { "<leader>oD", function() vim.g.opencode_restart_with_model(vim.g.opencode_model_deepseek) end, desc = "Opencode Model: DeepSeek" },
    { "<leader>o0", function() vim.g.opencode_restart_with_model(vim.g.opencode_model_default) end, desc = "Opencode Model: Default" },
  },
}
