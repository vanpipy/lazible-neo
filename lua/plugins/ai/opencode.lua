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
    { "<leader>od", function() require("opencode").ask("Fix @diagnostics", { submit = true }) end,
      desc = "Opencode Fix Diagnostics" },
    { "<leader>or", function() require("opencode").ask("review @diff", { submit = true }) end,
      desc = "Opencode Review Diff" },
    {
      "<leader>oc",
      function()
        local function normalize_path(p)
          p = vim.fs.normalize(p)
          return (p:gsub("\\", "/"))
        end

        local function system_run(cmd, opts)
          opts = opts or {}
          if vim.system then
            local proc = vim.system(cmd, { cwd = opts.cwd, text = true, stdin = opts.stdin })
            local res = proc:wait()
            return res
          end
          local cwd_before = vim.fn.getcwd()
          if opts.cwd and opts.cwd ~= "" then
            pcall(vim.fn.chdir, opts.cwd)
          end
          local ok, out = pcall(vim.fn.system, cmd, opts.stdin)
          local code = vim.v.shell_error
          pcall(vim.fn.chdir, cwd_before)
          if not ok then
            return { code = 1, stdout = "", stderr = tostring(out) }
          end
          return { code = code, stdout = tostring(out), stderr = "" }
        end

        local function system_run_async(cmd, opts, on_exit)
          opts = opts or {}
          if vim.system then
            vim.system(
              cmd,
              {
                cwd = opts.cwd,
                text = true,
                stdin = opts.stdin,
                env = opts.env,
              },
              function(res)
                vim.schedule(function()
                  on_exit(res)
                end)
              end
            )
            return
          end
          vim.schedule(function()
            local res = system_run(cmd, opts)
            on_exit(res)
          end)
        end

        local function git_root()
          local ok_lv, root = pcall(function()
            if LazyVim and LazyVim.root and LazyVim.root.git then
              return LazyVim.root.git()
            end
          end)
          if ok_lv and type(root) == "string" and root ~= "" then
            return normalize_path(root)
          end
          local cwd = vim.fs.normalize((vim.uv or vim.loop).cwd() or ".")
          local res = system_run({ "git", "rev-parse", "--show-toplevel" }, { cwd = cwd })
          if type(res) == "table" and res.code == 0 and type(res.stdout) == "string" then
            local line = (res.stdout:gsub("%s+$", ""))
            if line ~= "" then
              return normalize_path(line)
            end
          end
          return nil
        end

        local function stage_all(root)
          local res = system_run({ "git", "add", "-A" }, { cwd = root })
          if type(res) ~= "table" or res.code ~= 0 then
            vim.notify("git add -A failed", vim.log.levels.ERROR)
          end
        end

        local function has_staged_changes(root)
          local res = system_run({ "git", "diff", "--cached", "--quiet" }, { cwd = root })
          if type(res) ~= "table" then
            return nil
          end
          if res.code == 0 then
            return false
          end
          if res.code == 1 then
            return true
          end
          return nil
        end

        local function opencode_ask_submit(prompt)
          local ok, opencode = pcall(require, "opencode")
          if not ok then
            vim.notify("opencode.nvim is not loaded", vim.log.levels.ERROR)
            return
          end

          if type(opencode.start) == "function" then
            pcall(opencode.start)
          elseif type(opencode.toggle) == "function" then
            pcall(opencode.toggle)
          end

          vim.defer_fn(function()
            local ok_ask, err = pcall(opencode.ask, prompt, { submit = true })
            if not ok_ask then
              vim.notify(("opencode ask failed: %s"):format(tostring(err)), vim.log.levels.ERROR)
            end
          end, 300)
        end

        local function ask_to_update_commit_file(commit_file)
          opencode_ask_submit(
            "Write a Git commit message based on @diff (Conventional Commits).\n"
              .. "Requirements:\n"
              .. "- Keep the first line under 72 characters\n"
              .. "- Format: <type>(<scope>): <subject>\n"
              .. "- Add a body/footer if needed (e.g. BREAKING CHANGE / issue)\n"
              .. "- Output should be a commit message only (no explanations)\n"
              .. "\n"
              .. "Then update @" .. commit_file .. ":\n"
              .. "- Replace only the actual commit message content (non-comment lines)\n"
              .. "- Keep all comment lines starting with # unchanged\n"
              .. "- Ensure the file begins with the new commit message\n"
          )
        end

        local root = git_root()
        if not root then
          vim.notify("not in a git repository", vim.log.levels.ERROR)
          return
        end
        stage_all(root)

        local staged = has_staged_changes(root)
        if staged == false then
          vim.notify("no staged changes to commit", vim.log.levels.WARN)
          return
        end

        local dir = vim.fs.joinpath(vim.fn.stdpath("state"), "opencode")
        vim.fn.mkdir(dir, "p")
        local commit_file = vim.fs.joinpath(dir, ("COMMIT_EDITMSG_%s.txt"):format(tostring(os.time())))
        vim.fn.writefile({}, commit_file)
        commit_file = normalize_path(commit_file)

        vim.cmd("tabnew " .. vim.fn.fnameescape(commit_file))
        vim.bo.filetype = "gitcommit"
        vim.bo.swapfile = false
        vim.bo.bufhidden = "wipe"
        vim.b.opencode_commit_root = root
        vim.b.opencode_commit_file = commit_file
        vim.b.opencode_commit_done = false
        vim.b.opencode_commit_inflight = false

        local bufnr = vim.api.nvim_get_current_buf()
        local augroup = vim.api.nvim_create_augroup(("opencode_commit_%d"):format(bufnr), { clear = true })

        vim.api.nvim_create_autocmd("BufWritePost", {
          group = augroup,
          buffer = bufnr,
          callback = function()
            if vim.b.opencode_commit_inflight == true or vim.b.opencode_commit_done == true then
              return
            end
            vim.b.opencode_commit_inflight = true

            local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
            local out = {}
            for _, l in ipairs(lines) do
              if type(l) == "string" and not l:match("^%s*#") then
                table.insert(out, l)
              end
            end
            while #out > 0 and out[#out]:match("^%s*$") do
              table.remove(out, #out)
            end

            local msg = table.concat(out, "\n"):gsub("%s+$", "")
            if msg == "" then
              vim.b.opencode_commit_inflight = false
              vim.notify("commit message is empty", vim.log.levels.WARN)
              return
            end

            vim.notify("creating git commit...", vim.log.levels.INFO)
            system_run_async(
              { "git", "commit", "-F", "-" },
              {
                cwd = vim.b.opencode_commit_root,
                stdin = msg .. "\n",
                env = { GIT_TERMINAL_PROMPT = "0" },
              },
              function(res)
                if type(res) == "table" and res.code == 0 then
                  vim.b.opencode_commit_done = true
                  vim.notify("git commit created", vim.log.levels.INFO)
                  pcall(vim.cmd, "tabclose")
                  return
                end
                local err = type(res) == "table" and ((res.stderr or "") .. (res.stdout or "")) or ""
                vim.notify(("git commit failed\n%s"):format(err), vim.log.levels.ERROR)
                vim.b.opencode_commit_inflight = false
              end
            )
          end,
        })

        vim.api.nvim_create_autocmd("BufWipeout", {
          group = augroup,
          buffer = bufnr,
          callback = function()
            if vim.b.opencode_commit_done == true then
              pcall(vim.fn.delete, vim.b.opencode_commit_file or "")
              return
            end
            pcall(vim.fn.delete, vim.b.opencode_commit_file or "")
          end,
        })

        ask_to_update_commit_file(commit_file)
      end,
      desc = "Opencode Commit Message (@diff)",
    },
    {
      "<leader>ov",
      function()
        pcall(vim.cmd, "DiffviewOpen")
        require("opencode").ask("review @diff", { submit = true })
      end,
      desc = "Opencode Review Diff (Diffview)",
    },
    { "<leader>oq", function() require("opencode").ask("Fix @quickfix", { submit = true }) end,
      desc = "Opencode Fix Quickfix" },
    { "<leader>ob", function() require("opencode").ask("Summarize @buffer", { submit = true }) end,
      desc = "Opencode Summarize Buffer" },
    { "<leader>oe", function() require("opencode").ask("Explain @this", { submit = true }) end,
      desc = "Opencode Explain", mode = { "n", "v" } },
    { "<leader>ot", function() require("opencode").ask("Write unit tests for @this", { submit = true }) end,
      desc = "Opencode Write Tests", mode = { "n", "v" } },
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
    { "<leader>oR", function() 
      vim.g.opencode_restart_with_model(nil) 
    end, desc = "Opencode Restart" },
  },
}
