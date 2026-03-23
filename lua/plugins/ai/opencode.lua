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
    vim.g.opencode_model_default = vim.env.OPENCODE_MODEL_DEFAULT or ""
    vim.g.opencode_model_deepseek = vim.env.OPENCODE_MODEL_DEEPSEEK or "deepseek/deepseek-chat"
    vim.g.opencode_restart_with_model = function(_)
      local ok, opencode = pcall(require, "opencode")
      if not ok then
        return
      end
      opencode.ask("/models", { submit = true })
    end
  end,
  config = function()
    vim.o.autoread = true
    local port = tonumber(vim.env.OPENCODE_PORT) or 4189
    local manage_server = vim.env.OPENCODE_NVIM_MANAGE_SERVER == "1" or vim.g.opencode_nvim_manage_server == true
    vim.g.opencode_nvim_manage_server = manage_server
    vim.g.opencode_nvim_server_job = nil
    vim.g.opencode_nvim_server_started = false

    local function lsof_listen_pids(p)
      if vim.fn.executable("lsof") ~= 1 then
        return nil
      end
      return vim.fn.systemlist({ "lsof", "-nP", "-iTCP:" .. tostring(p), "-sTCP:LISTEN", "-t" })
    end

    local function pid_is_opencode(pid)
      if vim.fn.executable("ps") ~= 1 then
        return true
      end
      local args = vim.fn.systemlist({ "ps", "-p", tostring(pid), "-o", "args=" })
      local line = type(args) == "table" and args[1] or ""
      return type(line) == "string" and line:match("opencode") ~= nil
    end

    local function detect_server(p)
      local pids = lsof_listen_pids(p)
      if type(pids) ~= "table" or #pids == 0 then
        return { status = "free" }
      end
      for _, pid in ipairs(pids) do
        if pid and pid ~= "" and pid_is_opencode(pid) then
          return { status = "opencode", pids = pids }
        end
      end
      return { status = "busy", pids = pids }
    end

    local function kill_opencode_on_port(p)
      if vim.fn.executable("kill") ~= 1 then
        return
      end
      local info = detect_server(p)
      if info.status ~= "opencode" then
        return
      end
      local pids = info.pids or {}
      for _, pid in ipairs(pids) do
        if pid and pid ~= "" and pid_is_opencode(pid) then
          pcall(vim.fn.system, { "kill", "-TERM", tostring(pid) })
        end
      end
      vim.wait(800, function()
        return detect_server(p).status == "free"
      end, 50)
      if detect_server(p).status ~= "free" then
        for _, pid in ipairs(pids) do
          if pid and pid ~= "" and pid_is_opencode(pid) then
            pcall(vim.fn.system, { "kill", "-KILL", tostring(pid) })
          end
        end
      end
    end

    local function start_managed_server()
      if not manage_server then
        return
      end
      local info = detect_server(port)
      if info.status == "opencode" then
        return
      end
      if info.status == "busy" then
        vim.notify(("opencode port %d is in use by another process"):format(port), vim.log.levels.ERROR)
        return
      end
      local jid = vim.fn.jobstart({ "opencode", "--port", tostring(port) }, { detach = true })
      if type(jid) ~= "number" or jid <= 0 then
        vim.notify("failed to start opencode server", vim.log.levels.ERROR)
        return
      end
      vim.g.opencode_nvim_server_job = jid
      vim.g.opencode_nvim_server_started = true
      vim.wait(1500, function()
        return detect_server(port).status == "opencode"
      end, 50)
    end

    local function stop_managed_server()
      if not manage_server then
        return
      end
      if vim.g.opencode_nvim_server_started ~= true then
        return
      end
      local jid = vim.g.opencode_nvim_server_job
      if type(jid) == "number" and jid > 0 then
        pcall(vim.fn.jobstop, jid)
      end
      kill_opencode_on_port(port)
      vim.g.opencode_nvim_server_job = nil
      vim.g.opencode_nvim_server_started = false
    end

    vim.g.opencode_opts = {
      port = port,
      lsp = { enabled = true },
      server = {
        start = start_managed_server,
        stop = stop_managed_server,
      },
    }

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

    vim.api.nvim_create_autocmd("TermOpen", {
      callback = function(args)
        local buf = args.buf
        if not buf or not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        local name = vim.api.nvim_buf_get_name(buf)
        name = type(name) == "string" and name:lower() or ""
        if not name:match("opencode") then
          return
        end
        vim.keymap.set("t", "<C-h>", [[<C-\><C-n><C-w>h]], { buffer = buf, silent = true, noremap = true })
        vim.keymap.set("t", "<C-j>", [[<C-\><C-n><C-w>j]], { buffer = buf, silent = true, noremap = true })
        vim.keymap.set("t", "<C-k>", [[<C-\><C-n><C-w>k]], { buffer = buf, silent = true, noremap = true })
        vim.keymap.set("t", "<C-l>", [[<C-\><C-n><C-w>l]], { buffer = buf, silent = true, noremap = true })
      end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
      callback = function()
        pcall(stop_managed_server)
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
