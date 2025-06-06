return {
  "Kurama622/llm.nvim",
  dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim" },
  cmd = { "LLMSessionToggle", "LLMSelectedTextHandler", "LLMAppHandler" },
  config = function()
    local tools = require("llm.tools")

    require("llm").setup({
      -- [[ Deepseek ]]
      url = "https://api.deepseek.com/chat/completions",
      model = "deepseek-chat",
      api_type = "openai",
      max_tokens = 4096,
      temperature = 0.3,
      top_p = 0.7,

      prompt = "You are a helpful chinese assistant.",

      prefix = {
        user = { text = "😃 ", hl = "Title" },
        assistant = { text = "  ", hl = "Added" },
      },

      -- history_path = "/tmp/llm-history",
      save_session = true,
      max_history = 15,
      max_history_name_length = 20,

        -- stylua: ignore
        keys = {
          -- The keyboard mapping for the input window.
          ["Input:Submit"]      = { mode = "n", key = "<cr>" },
          ["Input:Cancel"]      = { mode = {"n", "i"}, key = "<C-c>" },
          ["Input:Resend"]      = { mode = {"n", "i"}, key = "<C-r>" },

          -- only works when "save_session = true"
          ["Input:HistoryNext"] = { mode = {"n", "i"}, key = "<C-j>" },
          ["Input:HistoryPrev"] = { mode = {"n", "i"}, key = "<C-k>" },

          -- The keyboard mapping for the output window in "split" style.
          ["Output:Ask"]        = { mode = "n", key = "i" },
          ["Output:Cancel"]     = { mode = "n", key = "<C-c>" },
          ["Output:Resend"]     = { mode = "n", key = "<C-r>" },

          -- The keyboard mapping for the output and input windows in "float" style.
          ["Session:Toggle"]    = { mode = "n", key = "<leader>ac" },
          ["Session:Close"]     = { mode = "n", key = {"<esc>", "Q"} },

          -- Scroll
          ["PageUp"]            = { mode = {"i","n"}, key = "<C-b>" },
          ["PageDown"]          = { mode = {"i","n"}, key = "<C-f>" },
          ["HalfPageUp"]        = { mode = {"i","n"}, key = "<C-u>" },
          ["HalfPageDown"]      = { mode = {"i","n"}, key = "<C-d>" },
          ["JumpToTop"]         = { mode = "n", key = "gg" },
          ["JumpToBottom"]      = { mode = "n", key = "G" },
        },

      -- display diff [require by action_handler]
      display = {
        diff = {
          layout = "vertical", -- vertical|horizontal split for default provider
          opts = { "internal", "filler", "closeoff", "algorithm:patience", "followwrap", "linematch:120" },
          provider = "mini_diff", -- default|mini_diff
        },
      },
      app_handler = {
        -- Your AI tools Configuration
        -- TOOL_NAME = { ... }
        Completion = {
          handler = tools.completion_handler,
          opts = {
            -------------------------------------------------
            ---                   ollama
            -------------------------------------------------
            -- url = "http://localhost:11434/v1/completions",
            -- model = "qwen2.5-coder:1.5b",
            -- api_type = "ollama",
            ------------------- end ollama ------------------

            -------------------------------------------------
            ---                  deepseek
            -------------------------------------------------
            url = "https://api.deepseek.com/beta/completions",
            model = "deepseek-chat",
            api_type = "deepseek",
            fetch_key = function()
              return vim.env.LLM_KEY
            end,
            ------------------ end deepseek -----------------

            -------------------------------------------------
            ---                 siliconflow
            -------------------------------------------------
            -- url = "https://api.siliconflow.cn/v1/completions",
            -- model = "Qwen/Qwen2.5-Coder-7B-Instruct",
            -- api_type = "openai",
            -- fetch_key = function()
            --   return "your api key"
            -- end,
            ------------------ end siliconflow -----------------

            -------------------------------------------------
            ---                  codeium
            ---    dependency: "Exafunction/codeium.nvim"
            -------------------------------------------------
            -- api_type = "codeium",
            ------------------ end codeium ------------------

            n_completions = 3,
            context_window = 512,
            max_tokens = 256,

            -- A mapping of filetype to true or false, to enable completion.
            filetypes = { sh = false },

            -- Whether to enable completion of not for filetypes not specifically listed above.
            default_filetype_enabled = true,

            auto_trigger = true,

            -- just trigger by { "@", ".", "(", "[", ":", " " } for `style = "nvim-cmp"`
            only_trigger_by_keywords = true,

            style = "virtual_text", -- nvim-cmp or blink.cmp

            timeout = 10, -- max request time

            -- only send the request every x milliseconds, use 0 to disable throttle.
            throttle = 1000,
            -- debounce the request in x milliseconds, set to 0 to disable debounce
            debounce = 400,

            keymap = {
              virtual_text = {
                accept = {
                  mode = "i",
                  keys = "<A-a>",
                },
                next = {
                  mode = "i",
                  keys = "<A-n>",
                },
                prev = {
                  mode = "i",
                  keys = "<A-p>",
                },
              },
            },
          },
        },
      },
    })
  end,
  keys = {
    { "<leader>ac", mode = "n", "<cmd>LLMSessionToggle<cr>" },
    { "<leader>ae", mode = "v", "<cmd>LLMSelectedTextHandler please explain the codes<cr>" },
    { "<leader>ts", mode = "x", "<cmd>LLMSelectedTextHandler en to cn<cr>" },
  },
}
