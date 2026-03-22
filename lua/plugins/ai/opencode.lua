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
    -- 基础配置
    local port = tonumber(vim.env.OPENCODE_PORT) or 4189
    local log_level = vim.env.OPENCODE_LOG_LEVEL or "DEBUG"
    
    -- 构建启动命令（添加必要的参数）
    local function build_base_cmd()
      local cmd_parts = {
        "opencode",
        "--port", tostring(port),
        "--print-logs",
        "--log-level", log_level,
      }
      
      -- 添加配置文件路径（确保读取正确的配置）
      local config_path = os.getenv("HOME") .. "/.config/opencode/opencode.json"
      if vim.fn.filereadable(config_path) == 1 then
        table.insert(cmd_parts, "--config")
        table.insert(cmd_parts, config_path)
      end
      
      return cmd_parts
    end
    
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
    
    -- 存储当前使用的模型和命令
    vim.g.opencode_model_default = vim.env.OPENCODE_MODEL_DEFAULT or ""
    vim.g.opencode_model_deepseek = vim.env.OPENCODE_MODEL_DEEPSEEK or "deepseek/deepseek-v3.2"
    vim.g.opencode_current_cmd = build_base_cmd()
    
    -- 构建带模型的命令
    local function build_cmd_with_model(model)
      local cmd = build_base_cmd()
      if model and model ~= "" then
        table.insert(cmd, "--model")
        table.insert(cmd, model)
      end
      return cmd
    end
    
    vim.g.opencode_snacks_terminal_opts = {
      win = {
        position = "right",
        enter = true,
        on_win = function(win)
          require("opencode.terminal").setup(win.win)
        end,
      },
    }
    
    local function term_opts()
      if vim.g.opencode_term_opts ~= nil then
        return vim.g.opencode_term_opts
      end
      vim.g.opencode_term_opts = vim.tbl_deep_extend("force", vim.g.opencode_snacks_terminal_opts, {
        cwd = root_dir(),
      })
      return vim.g.opencode_term_opts
    end
    
    -- 重启函数（切换模型）
    vim.g.opencode_restart_with_model = function(model)
      local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
      if not ok_term then
        vim.notify("snacks.nvim not available", vim.log.levels.ERROR)
        return
      end
      
      -- 关闭现有终端
      local current_cmd_str = table.concat(vim.g.opencode_current_cmd, " ")
      local term = snacks_terminal.get(current_cmd_str, term_opts())
      if term then
        term:close()
      end
      
      -- 重置状态
      vim.g.opencode_term_opts = nil
      
      -- 构建新命令
      vim.g.opencode_current_cmd = build_cmd_with_model(model)
      
      -- 打开新终端
      local success, err = pcall(function()
        snacks_terminal.open(vim.g.opencode_current_cmd, term_opts())
      end)
      
      if not success then
        vim.notify("Failed to start opencode: " .. tostring(err), vim.log.levels.ERROR)
      else
        vim.notify("Switched to model: " .. model, vim.log.levels.INFO)
      end
    end
    
    -- 配置 opencode 插件
    vim.g.opencode_opts = {
      port = port,
      lsp = { enabled = true },
      server = {
        start = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            vim.notify("snacks.nvim not available", vim.log.levels.ERROR)
            return
          end
          
          -- 确保配置存在
          local config_path = os.getenv("HOME") .. "/.config/opencode/opencode.json"
          if vim.fn.filereadable(config_path) == 0 then
            vim.notify(
              "opencode.json not found at " .. config_path,
              vim.log.levels.WARN
            )
          end
          
          vim.g.opencode_term_opts = nil
          snacks_terminal.open(vim.g.opencode_current_cmd, term_opts())
        end,
        stop = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            return
          end
          local current_cmd_str = table.concat(vim.g.opencode_current_cmd, " ")
          local term = snacks_terminal.get(current_cmd_str, term_opts())
          if term then
            term:close()
          end
          vim.g.opencode_term_opts = nil
        end,
        toggle = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            return
          end
          snacks_terminal.toggle(vim.g.opencode_current_cmd, term_opts())
        end,
      },
    }
  end,
  config = function()
    vim.o.autoread = true
    
    -- 安全包装 ask 函数，防止 nil prompt
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
    
    -- 检查 opencode 是否可用
    local function check_opencode()
      if vim.fn.executable("opencode") == 0 then
        vim.notify(
          "opencode not found in PATH. Please install it first.",
          vim.log.levels.ERROR
        )
        return false
      end
      
      local config_path = os.getenv("HOME") .. "/.config/opencode/opencode.json"
      if vim.fn.filereadable(config_path) == 0 then
        vim.notify(
          "opencode.json not found at " .. config_path,
          vim.log.levels.WARN
        )
      end
      
      return true
    end
    
    -- 延迟检查，避免影响启动速度
    vim.defer_fn(function()
      check_opencode()
    end, 1000)
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
    { "<leader>ol", "<cmd>lua vim.g.opencode_restart_with_model('')<cr>", 
      desc = "Opencode Reload" },
  },
}