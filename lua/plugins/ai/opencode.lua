return {
  "nickjvandyke/opencode.nvim",
  version = "*",
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
  config = function()
    local ok_term, snacks_terminal = pcall(require, "snacks.terminal")
    local port = tonumber(vim.env.OPENCODE_PORT) or 4189
    local function build_cmd(model)
      if model and model ~= "" then
        return ("opencode --port %d --model %s"):format(port, model)
      end
      return ("opencode --port %d"):format(port)
    end

    local default_model = vim.env.OPENCODE_MODEL_DEFAULT
    local deepseek_model = vim.env.OPENCODE_MODEL_DEEPSEEK or "deepseek/deepseek-chat"
    local current_cmd = build_cmd(default_model)
    local snacks_terminal_opts = {
      win = {
        position = "right",
        enter = false,
        on_win = function(win)
          require("opencode.terminal").setup(win.win)
        end,
      },
    }

    vim.g.opencode_opts = {
      port = port,
      lsp = { enabled = true },
      server = ok_term and {
        start = function()
          snacks_terminal.open(current_cmd, snacks_terminal_opts)
        end,
        stop = function()
          local term = snacks_terminal.get(current_cmd, snacks_terminal_opts)
          if term then
            term:close()
          end
        end,
        toggle = function()
          snacks_terminal.toggle(current_cmd, snacks_terminal_opts)
        end,
      } or nil,
    }

    local function restart_with_cmd(cmd)
      if not ok_term then
        return
      end

      local term = snacks_terminal.get(current_cmd, snacks_terminal_opts)
      if term then
        term:close()
      end
      current_cmd = cmd
      snacks_terminal.open(current_cmd, snacks_terminal_opts)
    end

    local map = vim.keymap.set
    map({ "n", "v" }, "<leader>oa", function()
      require("opencode").ask()
    end, { desc = "Opencode Ask" })
    map("n", "<leader>oo", function()
      require("opencode").toggle()
    end, { desc = "Opencode Toggle" })
    map("n", "<leader>os", function()
      require("opencode").select()
    end, { desc = "Opencode Select" })
    map("n", "<leader>op", function()
      require("opencode").prompt()
    end, { desc = "Opencode Prompt" })
    map("n", "<leader>oh", "<cmd>checkhealth opencode<cr>", { desc = "Opencode Health" })
    map("n", "<leader>oM", function()
      require("opencode").ask("/models", { submit = true })
    end, { desc = "Opencode Models" })
    map("n", "<leader>oC", function()
      require("opencode").ask("/connect", { submit = true })
    end, { desc = "Opencode Connect" })
    map("n", "<leader>oD", function()
      restart_with_cmd(build_cmd(deepseek_model))
    end, { desc = "Opencode Model: DeepSeek" })
    map("n", "<leader>o0", function()
      restart_with_cmd(build_cmd(default_model))
    end, { desc = "Opencode Model: Default" })
  end,
}
