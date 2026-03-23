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
    local opencode_bin_cache = nil

    local function resolve_opencode_bin()
      if opencode_bin_cache ~= nil then
        return opencode_bin_cache
      end
      local p = vim.fn.exepath("opencode")
      if type(p) == "string" and p ~= "" then
        opencode_bin_cache = p
        return p
      end
      local home = vim.env.HOME or vim.fn.expand("~")
      local fallback = vim.fs.joinpath(home, ".opencode", "bin", "opencode")
      if vim.fn.executable(fallback) == 1 then
        opencode_bin_cache = fallback
        return fallback
      end
      opencode_bin_cache = "opencode"
      return opencode_bin_cache
    end
    vim.g.opencode_resolve_bin = resolve_opencode_bin

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
      local bin = resolve_opencode_bin()
      local jid = vim.fn.jobstart({ bin, "--port", tostring(port) }, { detach = true })
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
        local ok_flow, flow_err = xpcall(function()
        local function resolve_opencode_bin()
          local f = vim.g.opencode_resolve_bin
          if type(f) == "function" then
            local ok, bin = pcall(f)
            if ok and type(bin) == "string" and bin ~= "" then
              return bin
            end
          end
          local p = vim.fn.exepath("opencode")
          if type(p) == "string" and p ~= "" then
            return p
          end
          local home = vim.env.HOME or vim.fn.expand("~")
          local fallback = vim.fs.joinpath(home, ".opencode", "bin", "opencode")
          if vim.fn.executable(fallback) == 1 then
            return fallback
          end
          return "opencode"
        end

        local function normalize_path(p)
          p = vim.fs.normalize(p)
          return (p:gsub("\\", "/"))
        end

        local function system_run(cmd, opts)
          opts = opts or {}
          local env_before = nil
          if type(opts.env) == "table" then
            env_before = {}
            for k, v in pairs(opts.env) do
              env_before[k] = vim.env[k]
              vim.env[k] = v
            end
          end
          if vim.system then
            local proc = vim.system(cmd, { cwd = opts.cwd, text = true, stdin = opts.stdin, env = opts.env })
            local res = proc:wait()
            if env_before then
              for k, v in pairs(env_before) do
                vim.env[k] = v
              end
            end
            return res
          end
          local cwd_before = vim.fn.getcwd()
          if opts.cwd and opts.cwd ~= "" then
            pcall(vim.fn.chdir, opts.cwd)
          end
          local ok, out = pcall(vim.fn.system, cmd, opts.stdin)
          local code = vim.v.shell_error
          pcall(vim.fn.chdir, cwd_before)
          if env_before then
            for k, v in pairs(env_before) do
              vim.env[k] = v
            end
          end
          if not ok then
            return { code = 1, stdout = "", stderr = tostring(out) }
          end
          return { code = code, stdout = tostring(out), stderr = "" }
        end

        local function system_run_async(cmd, opts, on_exit)
          opts = opts or {}
          if vim.system then
            local proc = vim.system(
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
            return proc
          end
          vim.schedule(function()
            local res = system_run(cmd, opts)
            on_exit(res)
          end)
          return nil
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

        local function replace_gitcommit_message(bufnr, message)
          local function split_lines(s)
            local t = {}
            for line in (s .. "\n"):gmatch("(.-)\n") do
              table.insert(t, line)
            end
            while #t > 0 and t[#t]:match("^%s*$") do
              table.remove(t, #t)
            end
            return t
          end

          local function cleanup_message(s)
            s = (s or ""):gsub("\r\n", "\n")
            s = s:gsub("\27%[[0-9;]*m", "")

            local lines = vim.split(s, "\n", { plain = true })
            local fence_start = nil
            for i, l in ipairs(lines) do
              if type(l) == "string" and l:match("^%s*```") then
                fence_start = i
                break
              end
            end
            if fence_start then
              local captured = {}
              for i = fence_start + 1, #lines do
                local l = lines[i]
                if type(l) == "string" and l:match("^%s*```%s*$") then
                  break
                end
                table.insert(captured, l)
              end
              s = table.concat(captured, "\n")
            end

            s = s:gsub("^%s+", ""):gsub("%s+$", "")
            s = s:gsub("^Commit message:%s*", "")
            s = s:gsub("^Here is the commit message:%s*", "")

            local allowed = {
              feat = true,
              fix = true,
              docs = true,
              style = true,
              refactor = true,
              perf = true,
              test = true,
              build = true,
              ci = true,
              chore = true,
              revert = true,
            }

            local function looks_like_conventional_header(l)
              l = (l or ""):gsub("^%s+", ""):gsub("%s+$", "")
              if l == "" then
                return false
              end
              local t = l:match("^([%a]+)")
              if not t or not allowed[t] then
                return false
              end
              if l:match("^" .. t .. "%:%s+.+") then
                return true
              end
              if l:match("^" .. t .. "!%:%s+.+") then
                return true
              end
              if l:match("^" .. t .. "%b()%:%s+.+") then
                return true
              end
              if l:match("^" .. t .. "%b()!%:%s+.+") then
                return true
              end
              return false
            end

            local post_lines = vim.split(s, "\n", { plain = true })
            for i, l in ipairs(post_lines) do
              if looks_like_conventional_header(l) then
                local kept = {}
                for j = i, #post_lines do
                  table.insert(kept, post_lines[j])
                end
                s = table.concat(kept, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
                break
              end
            end

            local first = nil
            for _, l in ipairs(vim.split(s, "\n", { plain = true })) do
              if type(l) == "string" and not l:match("^%s*$") then
                first = l
                break
              end
            end
            if not looks_like_conventional_header(first) then
              return ""
            end

            return s
          end

          message = cleanup_message(message)
          local msg_lines = split_lines(message)
          if #msg_lines == 0 then
            vim.notify("opencode produced an empty commit message", vim.log.levels.WARN)
            return false
          end

          local old = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
          local comment_start = nil
          for i, l in ipairs(old) do
            if type(l) == "string" and l:match("^%s*#") then
              comment_start = i
              break
            end
          end

          local comments = {}
          if comment_start then
            for i = comment_start, #old do
              table.insert(comments, old[i])
            end
          end

          local new_lines = {}
          for _, l in ipairs(msg_lines) do
            table.insert(new_lines, l)
          end
          if #comments > 0 then
            if #new_lines > 0 and not new_lines[#new_lines]:match("^%s*$") then
              table.insert(new_lines, "")
            end
            for _, l in ipairs(comments) do
              table.insert(new_lines, l)
            end
          end

          vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
          vim.api.nvim_win_set_cursor(0, { 1, 0 })
          return true
        end

        local function opencode_run_commit_message(root, on_done)
          local bin = resolve_opencode_bin()
          if vim.fn.executable(bin) ~= 1 then
            on_done({ ok = false, err = ("opencode is not found or not executable: %s"):format(tostring(bin)), stdout = "" })
            return nil
          end

          local diff = system_run({ "git", "diff", "--cached" }, { cwd = root })
          if type(diff) ~= "table" or diff.code ~= 0 then
            local err = type(diff) == "table" and ((diff.stderr or "") .. (diff.stdout or "")) or ""
            on_done({ ok = false, err = "failed to get staged diff\n" .. err, stdout = "" })
            return nil
          end

          local dir = vim.fs.joinpath(vim.fn.stdpath("state"), "opencode")
          vim.fn.mkdir(dir, "p")
          local diff_file = vim.fs.joinpath(dir, ("STAGED_DIFF_%s.patch"):format(tostring(os.time())))
          vim.fn.writefile(vim.split(diff.stdout or "", "\n", { plain = true }), diff_file)
          diff_file = normalize_path(diff_file)

          local prompt = table.concat({
            "Write a Git commit message for the changes in the attached git diff.",
            "",
            "Requirements:",
            "- Use Conventional Commits: <type>(<scope>): <subject>",
            "- Keep the subject line under 72 characters",
            "- Add a body/footer only if needed (e.g. BREAKING CHANGE / issue references)",
            "- Output ONLY the commit message text",
            "- Start the output with the subject line",
            "- Do NOT include analysis, headings, bullet lists, or markdown/code fences",
            "- Do NOT request or run git commands; use the attached diff file only",
          }, "\n")

          local opencode_cwd = root
          local root_cfg = vim.fs.joinpath(root, "opencode.json")
          if vim.fn.filereadable(root_cfg) ~= 1 then
            local nvim_cfg_dir = vim.fn.stdpath("config")
            local nvim_cfg = vim.fs.joinpath(nvim_cfg_dir, "opencode.json")
            if vim.fn.filereadable(nvim_cfg) == 1 then
              opencode_cwd = nvim_cfg_dir
            end
          end

          local env = nil
          do
            local nvim_cfg_dir = vim.fn.stdpath("config")
            local nvim_cfg = vim.fs.joinpath(nvim_cfg_dir, "opencode.json")
            if vim.fn.filereadable(nvim_cfg) == 1 then
              env = { OPENCODE_CONFIG = normalize_path(nvim_cfg) }
            end
          end

          local done = false
          local function finish(res)
            if done then
              return
            end
            done = true
            on_done(res)
          end

          local proc = system_run_async(
            { bin, "run", "--agent=commit", "--dir=" .. root, "--file=" .. diff_file, "--", prompt },
            { cwd = opencode_cwd, env = env },
            function(res)
              pcall(vim.fn.delete, diff_file)
              if type(res) ~= "table" then
                finish({ ok = false, err = "opencode run failed (no result)", stdout = "" })
                return
              end
              if res.code == 0 then
                finish({ ok = true, err = "", stdout = res.stdout or "" })
                return
              end
              local err = (res.stderr or "") .. (res.stdout or "")
              finish({
                ok = false,
                err = err ~= "" and err or ("opencode run failed (code " .. tostring(res.code) .. ")"),
                stdout = res.stdout or "",
              })
            end
          )

          vim.defer_fn(function()
            if done then
              return
            end
            if proc and type(proc.kill) == "function" then
              pcall(proc.kill, proc, 15)
              pcall(vim.fn.delete, diff_file)
              finish({ ok = false, err = "opencode run timed out (aborted)", stdout = "" })
            end
          end, 60000)

          return proc
        end

        if vim.fn.executable("git") ~= 1 then
          vim.notify("git is not found in PATH", vim.log.levels.ERROR)
          return
        end

        local root = git_root()
        if not root then
          vim.notify("not in a git repository", vim.log.levels.ERROR)
          return
        end
        local staged = has_staged_changes(root)
        if staged == false then
          vim.notify("no staged changes to commit. stage your changes first (git add) and retry.", vim.log.levels.WARN)
          return
        end
        if staged == nil then
          vim.notify("unable to determine staged changes", vim.log.levels.WARN)
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
        local commit_proc = nil
        local run_proc = nil

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
            local proc = system_run_async(
              { "git", "commit", "-F", "-" },
              {
                cwd = vim.b.opencode_commit_root,
                stdin = msg .. "\n",
                env = {
                  GIT_TERMINAL_PROMPT = "0",
                  GIT_EDITOR = "true",
                  GIT_SEQUENCE_EDITOR = "true",
                },
              },
              function(res)
                if type(res) == "table" and res.code == 0 then
                  vim.b.opencode_commit_done = true
                  commit_proc = nil
                  vim.notify("git commit created", vim.log.levels.INFO)
                  pcall(vim.cmd, "tabclose")
                  return
                end
                local err = type(res) == "table" and ((res.stderr or "") .. (res.stdout or "")) or ""
                vim.notify(("git commit failed\n%s"):format(err), vim.log.levels.ERROR)
                vim.b.opencode_commit_inflight = false
                commit_proc = nil
              end
            )
            commit_proc = proc
            vim.defer_fn(function()
              if vim.b.opencode_commit_inflight ~= true or vim.b.opencode_commit_done == true then
                return
              end
              local p = commit_proc
              if p and type(p.kill) == "function" then
                pcall(p.kill, p, 15)
              end
              commit_proc = nil
              vim.b.opencode_commit_inflight = false
              vim.notify("git commit timed out (aborted)", vim.log.levels.ERROR)
            end, 20000)
          end,
        })

        vim.api.nvim_create_autocmd("BufWipeout", {
          group = augroup,
          buffer = bufnr,
          callback = function()
            local p = commit_proc
            if p and type(p.kill) == "function" then
              pcall(p.kill, p, 15)
            end
            commit_proc = nil
            local r = run_proc
            if r and type(r.kill) == "function" then
              pcall(r.kill, r, 15)
            end
            run_proc = nil
            if vim.b.opencode_commit_done == true then
              pcall(vim.fn.delete, vim.b.opencode_commit_file or "")
              return
            end
            pcall(vim.fn.delete, vim.b.opencode_commit_file or "")
          end,
        })

        vim.notify("generating commit message...", vim.log.levels.INFO)
        run_proc = opencode_run_commit_message(root, function(result)
          if not vim.api.nvim_buf_is_valid(bufnr) then
            return
          end
          if result.ok then
            local ok_replace = replace_gitcommit_message(bufnr, result.stdout)
            if ok_replace then
              vim.notify("commit message generated", vim.log.levels.INFO)
            end
            run_proc = nil
            return
          end
          run_proc = nil
          vim.notify(("opencode run failed; write the commit message manually, then :w to commit.\n%s"):format(tostring(result.err)), vim.log.levels.ERROR)
        end)
        end, function(e)
          return tostring(e)
        end)
        if not ok_flow then
          vim.notify(("opencode commit flow failed: %s"):format(tostring(flow_err)), vim.log.levels.ERROR)
        end
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
