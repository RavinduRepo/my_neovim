return {
  {
    "nvim-telescope/telescope.nvim",
    config = function(_, opts)
      require("telescope").setup(opts)

      local notes_dir = vim.fn.expand("~/Notes")
      local pdf_exports_dir = vim.fn.expand("~/Notes/pdf-exports")
      local current_project_path = nil
      local ns_id = vim.api.nvim_create_namespace("notes_tui_colors")

      local function ensure_dir(path)
        if vim.fn.isdirectory(path) == 0 then
          vim.fn.mkdir(path, "p")
        end
      end
      ensure_dir(notes_dir)
      ensure_dir(pdf_exports_dir)

      -- System file opener (OS Agnostic)
      local function open_system_app(path)
        if vim.ui.open then
          vim.ui.open(path)
        else
          local cmd
          if vim.fn.has("mac") == 1 then
            cmd = { "open", path }
          elseif vim.fn.has("unix") == 1 then
            cmd = { "xdg-open", path }
          elseif vim.fn.has("win32") == 1 then
            cmd = { "cmd", "/c", "start", '""', path }
          end
          if cmd then
            vim.fn.jobstart(cmd, { detach = true })
          end
        end
        vim.notify("Opened in system viewer", vim.log.levels.INFO, { title = "Notes System" })
      end

      -- Flat .md listing in one directory
      local function get_md_files(dir)
        local files = {}
        local handle = vim.loop.fs_scandir(dir)
        if handle then
          while true do
            local name, typ = vim.loop.fs_scandir_next(handle)
            if not name then
              break
            end
            if (typ == "file" or typ == "link") and name:match("%.md$") then
              table.insert(files, name)
            end
          end
        end
        table.sort(files)
        return files
      end

      local function collect_recursive(dir, depth, items)
        items = items or {}
        local entries = {}
        local handle = vim.loop.fs_scandir(dir)
        if handle then
          while true do
            local name, typ = vim.loop.fs_scandir_next(handle)
            if not name then
              break
            end
            if name:sub(1, 1) ~= "." and name ~= "pdf-exports" then
              table.insert(entries, { name = name, type = typ, path = dir .. "/" .. name })
            end
          end
        end
        table.sort(entries, function(a, b)
          if a.type == b.type then
            return a.name < b.name
          end
          return a.type == "file"
        end)
        for _, e in ipairs(entries) do
          if e.type == "file" and e.name:match("%.md$") then
            table.insert(items, { kind = "file", path = e.path, name = e.name, level = depth })
          elseif e.type == "directory" then
            table.insert(items, { kind = "heading", level = depth, name = e.name })
            collect_recursive(e.path, depth + 1, items)
          end
        end
        return items
      end

      local function file_title(name)
        return name:gsub("%.md$", ""):gsub("[_%-]", " ")
      end

      local function write_combined_md(items, title, out_path)
        local f = io.open(out_path, "w")
        if not f then
          return false
        end
        local safe_title = title:gsub("[_%-]", " "):gsub('"', '\\"')
        f:write('---\ntitle: "' .. safe_title .. '"\n---\n\n')

        for _, item in ipairs(items) do
          if item.kind == "heading" then
            local hashes = string.rep("#", item.level)
            f:write("\n" .. hashes .. " " .. item.name:gsub("[_%-]", " ") .. "\n\n")
          elseif item.kind == "file" then
            local hashes = string.rep("#", item.level)
            f:write("\n" .. hashes .. " " .. file_title(item.name) .. "\n\n")
            local src = io.open(item.path, "r")
            if src then
              local content = src:read("*a")
              src:close()
              f:write(content)
              if not content:match("\n$") then
                f:write("\n")
              end
              f:write("\n\n---\n\n")
            end
          end
        end
        f:close()
        return true
      end

      local function detect_pdf_engine()
        for _, e in ipairs({ "weasyprint", "wkhtmltopdf", "lualatex", "xelatex", "pdflatex" }) do
          if vim.fn.executable(e) == 1 then
            return e
          end
        end
        return nil
      end

      local function run_pandoc(engine, src_path, out_path, extra_flags, on_done)
        local engine_flag = "--pdf-engine=" .. engine
        local latex_extra = (engine:match("latex") or engine:match("tex")) and "-V geometry:margin=1in" or ""
        local cmd = string.format("pandoc %s %s %s %q -o %q", engine_flag, latex_extra, extra_flags, src_path, out_path)
        local stderr_out = {}
        local shell = vim.fn.has("win32") == 1 and { "cmd", "/c", cmd } or { "sh", "-c", cmd }
        vim.fn.jobstart(shell, {
          on_stderr = function(_, data)
            for _, l in ipairs(data) do
              if l ~= "" then
                table.insert(stderr_out, l)
              end
            end
          end,
          on_exit = function(_, code)
            on_done(code, table.concat(stderr_out, "\n"))
          end,
        })
      end

      local function do_export(mode, target_dir, target_file)
        if vim.fn.executable("pandoc") == 0 then
          vim.notify("pandoc not found. Install it first.", vim.log.levels.ERROR, { title = "Notes System" })
          return
        end
        local engine = detect_pdf_engine()
        if not engine then
          vim.notify(
            "No PDF engine found.\nInstall: sudo pacman -S python-weasyprint",
            vim.log.levels.ERROR,
            { title = "Notes System" }
          )
          return
        end
        ensure_dir(pdf_exports_dir)

        local function notify_ok(pdf_name)
          vim.notify("Saved → ~/Notes/pdf-exports/" .. pdf_name, vim.log.levels.INFO, { title = "Notes System" })
        end
        local function notify_fail(err)
          vim.notify("Export failed:\n" .. err, vim.log.levels.ERROR, { title = "Notes System" })
        end

        if mode == "file" then
          local src = target_dir .. "/" .. target_file
          local pname = target_file:gsub("%.md$", ".pdf")
          local out = pdf_exports_dir .. "/" .. pname
          vim.notify("Exporting " .. target_file .. " ...", vim.log.levels.INFO, { title = "Notes System" })
          run_pandoc(engine, src, out, "", function(code, err)
            if code == 0 then
              notify_ok(pname)
            else
              notify_fail(err)
            end
          end)
        elseif mode == "dir_recursive" then
          local dir_name = vim.fn.fnamemodify(target_dir, ":t")
          local items = collect_recursive(target_dir, 1)
          local file_count = 0
          for _, it in ipairs(items) do
            if it.kind == "file" then
              file_count = file_count + 1
            end
          end
          if file_count == 0 then
            vim.notify("No .md files found in " .. dir_name .. "/", vim.log.levels.WARN, { title = "Notes System" })
            return
          end

          local tmp = vim.fn.tempname() .. ".md"
          local pname = dir_name .. ".pdf"
          local out = pdf_exports_dir .. "/" .. pname
          if not write_combined_md(items, dir_name, tmp) then
            vim.notify("Could not create temp file.", vim.log.levels.ERROR, { title = "Notes System" })
            return
          end

          vim.notify(
            "Exporting " .. dir_name .. "/ (" .. file_count .. " notes, recursive) ...",
            vim.log.levels.INFO,
            { title = "Notes System" }
          )
          run_pandoc(engine, tmp, out, "--toc", function(code, err)
            os.remove(tmp)
            if code == 0 then
              notify_ok(pname)
            else
              notify_fail(err)
            end
          end)
        else
          local files = get_md_files(target_dir)
          if #files == 0 then
            vim.notify("No .md files in this directory.", vim.log.levels.WARN, { title = "Notes System" })
            return
          end
          local dir_name = vim.fn.fnamemodify(target_dir, ":t")
          local items = vim.tbl_map(function(f)
            return { kind = "file", path = target_dir .. "/" .. f, name = f, level = 1 }
          end, files)

          local tmp = vim.fn.tempname() .. ".md"
          local pname = dir_name .. ".pdf"
          local out = pdf_exports_dir .. "/" .. pname
          if not write_combined_md(items, dir_name, tmp) then
            vim.notify("Could not create temp file.", vim.log.levels.ERROR, { title = "Notes System" })
            return
          end

          vim.notify(
            "Exporting " .. #files .. " notes from " .. dir_name .. "/ ...",
            vim.log.levels.INFO,
            { title = "Notes System" }
          )
          run_pandoc(engine, tmp, out, "--toc", function(code, err)
            os.remove(tmp)
            if code == 0 then
              notify_ok(pname)
            else
              notify_fail(err)
            end
          end)
        end
      end

      -- THE UPGRADED TUI MANAGER
      local function open_notes_manager()
        local buf = vim.api.nvim_create_buf(false, true)

        -- Layout Math for side-by-side view
        local total_width = math.floor(vim.o.columns * 0.8)
        local width = math.floor(total_width / 2) - 1
        local height = math.floor(vim.o.lines * 0.7)
        local col = math.floor((vim.o.columns - total_width) / 2)
        local row = math.floor((vim.o.lines - height) / 2)

        local win = vim.api.nvim_open_win(buf, true, {
          relative = "editor",
          width = width,
          height = height,
          col = col,
          row = row,
          style = "minimal",
          border = "rounded",
          title = " Notes Manager ",
          title_pos = "center",
        })

        local current_view_dir = current_project_path or notes_dir

        -- Preview Window State
        local preview_buf = nil
        local preview_win = nil

        local function close_preview()
          if preview_win and vim.api.nvim_win_is_valid(preview_win) then
            vim.api.nvim_win_close(preview_win, true)
          end
          if preview_buf and vim.api.nvim_buf_is_valid(preview_buf) then
            vim.api.nvim_buf_delete(preview_buf, { force = true })
          end
          preview_win = nil
          preview_buf = nil
        end

        local function draw_ui()
          vim.bo[buf].modifiable = true
          local lines = {
            " 📁 " .. current_view_dir:gsub(vim.fn.expand("~"), "~"),
            " ──────────────────────────────────────────────",
            " [Space] Active | [<CR>] Edit | [o] Sys Open   ",
            " [a] Add | [d] Delete | [e] Export | [q] Close ",
            " ──────────────────────────────────────────────",
            "  ../",
          }

          local entries = {}
          local handle = vim.loop.fs_scandir(current_view_dir)
          if handle then
            while true do
              local name, typ = vim.loop.fs_scandir_next(handle)
              if not name then
                break
              end
              table.insert(entries, { name = name, type = typ })
            end
          end

          table.sort(entries, function(a, b)
            if a.type == b.type then
              return a.name < b.name
            end
            return a.type == "directory"
          end)

          for _, entry in ipairs(entries) do
            local prefix = entry.type == "directory" and "    " or "    "
            local suffix = entry.type == "directory" and "/" or ""
            table.insert(lines, prefix .. entry.name .. suffix)
          end

          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

          vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
          vim.api.nvim_buf_add_highlight(buf, ns_id, "Title", 0, 0, -1)
          for i = 1, 4 do
            vim.api.nvim_buf_add_highlight(buf, ns_id, "Comment", i, 0, -1)
          end
          vim.api.nvim_buf_add_highlight(buf, ns_id, "Directory", 5, 0, -1)

          for i, entry in ipairs(entries) do
            local hl_group = entry.type == "directory" and "Directory" or "String"
            vim.api.nvim_buf_add_highlight(buf, ns_id, hl_group, i + 5, 0, -1)
          end

          vim.bo[buf].modifiable = false
          vim.bo[buf].filetype = "notes_mgr"
          vim.api.nvim_win_set_cursor(win, { 6, 0 })
        end

        local function map(key, func)
          vim.keymap.set("n", key, func, { buffer = buf, silent = true, nowait = true })
        end

        -- Preview Autocommand
        vim.api.nvim_create_autocmd("CursorMoved", {
          buffer = buf,
          callback = function()
            local line = vim.api.nvim_get_current_line()
            local is_file = line:match("")
            local fname = is_file and line:match("%s*(.-)$")

            if is_file and fname and fname:match("%.md$") then
              local filepath = current_view_dir .. "/" .. fname
              if not preview_win or not vim.api.nvim_win_is_valid(preview_win) then
                preview_buf = vim.api.nvim_create_buf(false, true)
                preview_win = vim.api.nvim_open_win(preview_buf, false, {
                  relative = "editor",
                  width = width,
                  height = height,
                  col = col + width + 2,
                  row = row,
                  style = "minimal",
                  border = "rounded",
                  title = " Preview ",
                  title_pos = "center",
                })
              end
              local f_lines = {}
              if vim.fn.filereadable(filepath) == 1 then
                f_lines = vim.fn.readfile(filepath)
              end
              vim.bo[preview_buf].modifiable = true
              vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, f_lines)
              vim.bo[preview_buf].modifiable = false
              vim.bo[preview_buf].filetype = "markdown"
            else
              close_preview()
            end
          end,
        })

        -- Auto-clean preview on exit
        vim.api.nvim_create_autocmd({ "BufLeave", "BufWipeout" }, { buffer = buf, callback = close_preview })

        map("q", function()
          vim.api.nvim_win_close(win, true)
        end)
        map("-", function()
          current_view_dir = vim.fn.fnamemodify(current_view_dir, ":h")
          draw_ui()
        end)

        map("<CR>", function()
          local line = vim.api.nvim_get_current_line()
          if line:match("%.%./") then
            current_view_dir = vim.fn.fnamemodify(current_view_dir, ":h")
            draw_ui()
          elseif line:match("") then
            local dir = line:match("%s*(.-)/?$")
            current_view_dir = current_view_dir .. "/" .. dir
            draw_ui()
          elseif line:match("") then
            local file = line:match("%s*(.-)$")
            local filepath = current_view_dir .. "/" .. file
            if file:match("%.md$") then
              close_preview()
              vim.api.nvim_win_close(win, true)
              vim.cmd("e " .. vim.fn.fnameescape(filepath))
            else
              open_system_app(filepath)
            end
          end
        end)

        -- New: OS File/Dir Opener
        map("o", function()
          local line = vim.api.nvim_get_current_line()
          local target
          if line:match("%.%./") then
            target = vim.fn.fnamemodify(current_view_dir, ":h")
          elseif line:match("") then
            target = current_view_dir .. "/" .. (line:match("%s*(.-)/?$") or "")
          elseif line:match("") then
            target = current_view_dir .. "/" .. (line:match("%s*(.-)$") or "")
          else
            target = current_view_dir
          end
          if target and target ~= "" then
            open_system_app(target)
          end
        end)

        map("<Space>", function()
          current_project_path = current_view_dir
          vim.notify(
            "Active Notebook set to: " .. current_project_path,
            vim.log.levels.INFO,
            { title = "Notes System" }
          )
          close_preview()
          vim.api.nvim_win_close(win, true)
        end)

        map("a", function()
          vim.ui.input({ prompt = "Name (End with / for a folder): " }, function(input)
            if not input or input == "" then
              return
            end
            local path = current_view_dir .. "/" .. input
            if input:match("/$") then
              vim.fn.mkdir(path, "p")
            else
              io.open(path, "w"):close()
            end
            draw_ui()
          end)
        end)

        map("d", function()
          local line = vim.api.nvim_get_current_line()
          local target = line:match("%s*(.-)/?$") or line:match("%s*(.-)$")
          if not target then
            return
          end
          vim.ui.input({ prompt = "Delete " .. target .. "? (y/n): " }, function(input)
            if input == "y" then
              vim.fn.delete(current_view_dir .. "/" .. target, "rf")
              draw_ui()
            end
          end)
        end)

        map("e", function()
          local raw = vim.api.nvim_get_current_line()
          local name = raw:match("%s*(.-)/?$") or raw:match("%s*(.-)$") or raw:gsub("^%s+", ""):gsub("%s+$", "")

          if name:match("%.md$") then
            do_export("file", current_view_dir, name)
          elseif raw:match("") then
            do_export("dir_recursive", current_view_dir .. "/" .. name, nil)
          else
            do_export("dir_flat", current_view_dir, nil)
          end
        end)

        draw_ui()
      end

      -- Seamless Snippet Capture (with Topic List)
      local function capture_snippet()
        local ft = vim.bo.filetype
        local _, csrow, _, _ = unpack(vim.fn.getpos("'<"))
        local _, cerow, _, _ = unpack(vim.fn.getpos("'>"))
        local lines = vim.api.nvim_buf_get_lines(0, csrow - 1, cerow, false)

        if #lines == 0 then
          return
        end
        if not current_project_path then
          vim.notify("Open Notes Manager (<leader>mm) and hit Space to set active notebook!", vim.log.levels.ERROR)
          return
        end

        vim.ui.input({ prompt = "Snippet Explanation: " }, function(comment)
          if not comment then
            return
          end

          local files = { "✨ [ Create New Topic ]" }
          local handle = vim.loop.fs_scandir(current_project_path)
          if handle then
            while true do
              local name, typ = vim.loop.fs_scandir_next(handle)
              if not name then
                break
              end
              if typ == "file" and name:match("%.md$") then
                table.insert(files, name)
              end
            end
          end

          vim.ui.select(files, { prompt = "Select Destination Topic:" }, function(choice)
            if not choice then
              return
            end

            local function save_to_file(topic)
              if not topic:match("%.md$") then
                topic = topic .. ".md"
              end
              local filepath = current_project_path .. "/" .. topic
              local file = io.open(filepath, "a")
              file:write("\n### " .. os.date("%Y-%m-%d %H:%M") .. "\n")
              file:write(comment .. "\n\n```" .. ft .. "\n")
              for _, line in ipairs(lines) do
                file:write(line .. "\n")
              end
              file:write("```\n\n---\n")
              file:close()
              vim.notify("Saved to " .. topic, vim.log.levels.INFO, { title = "Notes System" })
            end

            if choice == "✨ [ Create New Topic ]" then
              vim.ui.input({ prompt = "New Topic Name: " }, function(new_topic)
                if new_topic and new_topic ~= "" then
                  save_to_file(new_topic)
                end
              end)
            else
              save_to_file(choice)
            end
          end)
        end)
      end

      -- Keybindings
      local wk = require("which-key")
      wk.add({ { "<leader>m", group = "Notes" } })

      vim.keymap.set("n", "<leader>mm", open_notes_manager, { desc = "Notes Manager" })
      vim.keymap.set("n", "<leader>mf", function()
        require("telescope.builtin").find_files({ cwd = notes_dir })
      end, { desc = "Find Notes" })
      vim.keymap.set("n", "<leader>mg", function()
        require("telescope.builtin").live_grep({ cwd = notes_dir })
      end, { desc = "Grep Notes" })

      -- New: Notes Lazygit
      vim.keymap.set("n", "<leader>mG", function()
        local ok, snacks = pcall(require, "snacks")
        if ok and snacks.lazygit then
          snacks.lazygit({ cwd = notes_dir })
        else
          vim.cmd("tabnew | tcd " .. vim.fn.fnameescape(notes_dir) .. " | term lazygit")
          vim.cmd("startinsert")
        end
      end, { desc = "Lazygit (Notes)" })

      vim.keymap.set("v", "<leader>ms", function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
        vim.schedule(capture_snippet)
      end, { desc = "Capture Snippet" })
    end,
  },
}
