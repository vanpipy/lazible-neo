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
    local function build_cmd(model)
      if model and model ~= "" then
        return ("opencode --port %d --model %s"):format(port, model)
      end
      return ("opencode --port %d"):format(port)
    end

    vim.g.opencode_model_default = vim.env.OPENCODE_MODEL_DEFAULT
    vim.g.opencode_model_deepseek = vim.env.OPENCODE_MODEL_DEEPSEEK or "deepseek/deepseek-chat"
    vim.g.opencode_cmd_current = build_cmd(vim.g.opencode_model_default)

    vim.g.opencode_snacks_terminal_opts = {
      win = {
        position = "right",
        enter = false,
        on_win = function(win)
          require("opencode.terminal").setup(win.win)
        end,
      },
    }

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

      vim.g.opencode_cmd_current = build_cmd(model)
      snacks_terminal.open(vim.g.opencode_cmd_current, opts)
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
          snacks_terminal.toggle(vim.g.opencode_cmd_current, vim.g.opencode_snacks_terminal_opts)
        end,
      },
    }
  end,
  keys = {
    { "<leader>o", group = "opencode" },
    { "<leader>oa", function() require("opencode").ask() end, desc = "Opencode Ask", mode = { "n", "v" } },
    { "<leader>oo", function() require("opencode").toggle() end, desc = "Opencode Toggle" },
    { "<leader>os", function() require("opencode").select() end, desc = "Opencode Select" },
    { "<leader>op", function() require("opencode").prompt() end, desc = "Opencode Prompt" },
    { "<leader>oh", "<cmd>checkhealth opencode<cr>", desc = "Opencode Health" },
    { "<leader>oM", function() require("opencode").ask("/models", { submit = true }) end, desc = "Opencode Models" },
    { "<leader>oC", function() require("opencode").ask("/connect", { submit = true }) end, desc = "Opencode Connect" },
    { "<leader>oD", function() vim.g.opencode_restart_with_model(vim.g.opencode_model_deepseek) end, desc = "Opencode Model: DeepSeek" },
    { "<leader>o0", function() vim.g.opencode_restart_with_model(vim.g.opencode_model_default) end, desc = "Opencode Model: Default" },
  },
}
