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
    local log_level = vim.env.OPENCODE_LOG_LEVEL or "INFO"
    local log_flags = ("--print-logs --log-level %s"):format(log_level)

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

    local function build_cmd(model)
      if model and model ~= "" then
        return ("opencode --port %d --model %s %s"):format(port, model, log_flags)
      end
      return ("opencode --port %d %s"):format(port, log_flags)
    end

    vim.g.opencode_model_default = vim.env.OPENCODE_MODEL_DEFAULT
    vim.g.opencode_model_deepseek = vim.env.OPENCODE_MODEL_DEEPSEEK or "deepseek/deepseek-chat"
    vim.g.opencode_cmd_current = build_cmd(vim.g.opencode_model_default)
    vim.g.opencode_term_opts = nil

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

    vim.g.opencode_restart_with_model = function(model)
      local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
      if not ok_term then
        return
      end
      local current_cmd = vim.g.opencode_cmd_current
      local opts = term_opts()
      local term = snacks_terminal.get(current_cmd, opts)
      if term then
        term:close()
      end
      vim.g.opencode_term_opts = nil
      vim.g.opencode_cmd_current = build_cmd(model)
      snacks_terminal.open(vim.g.opencode_cmd_current, term_opts())
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
          vim.g.opencode_term_opts = nil
          snacks_terminal.open(vim.g.opencode_cmd_current, term_opts())
        end,
        stop = function()
          local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
          if not ok_term then
            return
          end
          local term = snacks_terminal.get(vim.g.opencode_cmd_current, term_opts())
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
          snacks_terminal.toggle(vim.g.opencode_cmd_current, term_opts())
        end,
      },
    }
  end,
  config = function()
    vim.o.autoread = true
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
