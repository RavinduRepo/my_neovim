return {
  {
    "nvim-telescope/telescope.nvim",
    config = function(_, opts)
      require("telescope").setup(opts)

      local notes_dir = vim.fn.expand("~/Notes")
      local current_project_path = nil
      local ns_id = vim.api.nvim_create_namespace("notes_tui_colors")

      local function ensure_dir(path)
        if vim.fn.isdirectory(path) == 0 then
          vim.fn.mkdir(path, "p")
        end
      end
      ensure_dir(notes_dir)

      -- Enumerate .md files in a directory (Lua-side, avoids shell glob failures)
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

      -- Detect best available PDF engine in priority order.
      -- weasyprint and wkhtmltopdf need no LaTeX installation.
      -- Install on Arch:    sudo pacman -S python-weasyprint
      -- Install on Mac:     brew install weasyprint
      -- Install on Windows: pip install weasyprint
      local function detect_pdf_engine()
        for _, e in ipairs({ "weasyprint", "wkhtmltopdf", "lualatex", "xelatex", "pdflatex" }) do
          if vim.fn.executable(e) == 1 then
            return e
          end
        end
        return nil
      end

      -- Export Logic
      local function do_export(target_dir, target_file)
        if vim.fn.executable("pandoc") == 0 then
          vim.notify("pandoc not found. Install it first.", vim.log.levels.ERROR, { title = "Notes System" })
          return
        end

        local engine = detect_pdf_engine()
        if not engine then
          vim.notify(
            "No PDF engine found.\nInstall one of: python-weasyprint, wkhtmltopdf, or texlive",
            vim.log.levels.ERROR,
            { title = "Notes System" }
          )
          return
        end

        local engine_flag = "--pdf-engine=" .. engine
        -- LaTeX engines need explicit margins or text can overflow the page
        local extra = (engine:match("latex") or engine:match("tex")) and "-V geometry:margin=1in" or ""

        local cmd
        if target_file and target_file ~= "" and target_file:match("%.md$") then
          local pdf = target_file:gsub("%.md$", ".pdf")
          cmd = string.format("cd %q && pandoc %s %s %q -o %q", target_dir, engine_flag, extra, target_file, pdf)
          vim.notify("Exporting " .. target_file .. " ...", vim.log.levels.INFO, { title = "Notes System" })
        else
          -- Enumerate files in Lua so we never pass a bare *.md glob to the shell.
          -- (When no files match, shells pass the literal "*.md" to pandoc → crash.)
          local files = get_md_files(target_dir)
          if #files == 0 then
            vim.notify("No .md files in this directory.", vim.log.levels.WARN, { title = "Notes System" })
            return
          end
          local file_args = table.concat(
            vim.tbl_map(function(f)
              return string.format("%q", f)
            end, files),
            " "
          )
          cmd =
            string.format("cd %q && pandoc %s %s %s -o _Notebook_Export.pdf", target_dir, engine_flag, extra, file_args)
          vim.notify("Exporting " .. #files .. " notes ...", vim.log.levels.INFO, { title = "Notes System" })
        end

        local stderr_out = {}
        -- Windows uses cmd /c; Linux and Mac use sh -c
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
            if code == 0 then
              vim.notify("Export successful!", vim.log.levels.INFO, { title = "Notes System" })
            else
              vim.notify(
                "Export failed:\n" .. table.concat(stderr_out, "\n"),
                vim.log.levels.ERROR,
                { title = "Notes System" }
              )
            end
          end,
        })
      end

      -- THE TUI MANAGER (Now with Syntax Highlighting)
      local function open_notes_manager()
        local buf = vim.api.nvim_create_buf(false, true)
        local width = math.floor(vim.o.columns * 0.7)
        local height = math.floor(vim.o.lines * 0.7)
        local win = vim.api.nvim_open_win(buf, true, {
          relative = "editor",
          width = width,
          height = height,
          col = math.floor((vim.o.columns - width) / 2),
          row = math.floor((vim.o.lines - height) / 2),
          style = "minimal",
          border = "rounded",
          title = " Notes Manager ",
          title_pos = "center",
        })

        local current_view_dir = current_project_path or notes_dir

        local function draw_ui()
          vim.bo[buf].modifiable = true
          local lines = {
            " 📁 " .. current_view_dir:gsub(vim.fn.expand("~"), "~"),
            " ─────────────────────────────────────────────────────────────────",
            " [Space] Set active notebook | [<CR>] Open/Enter | [-] Go Up      ",
            " [a] Add File/Dir | [d] Delete | [e] Export PDF  | [q] Close      ",
            " ─────────────────────────────────────────────────────────────────",
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
            local prefix = entry.type == "directory" and "    " or "    "
            local suffix = entry.type == "directory" and "/" or ""
            table.insert(lines, prefix .. entry.name .. suffix)
          end

          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

          -- Apply Colors dynamically
          vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
          vim.api.nvim_buf_add_highlight(buf, ns_id, "Title", 0, 0, -1)
          for i = 1, 4 do
            vim.api.nvim_buf_add_highlight(buf, ns_id, "Comment", i, 0, -1)
          end
          vim.api.nvim_buf_add_highlight(buf, ns_id, "Directory", 5, 0, -1) -- Color the ../

          for i, entry in ipairs(entries) do
            local row = i + 5
            local hl_group = entry.type == "directory" and "Directory" or "String"
            vim.api.nvim_buf_add_highlight(buf, ns_id, hl_group, row, 0, -1)
          end

          vim.bo[buf].modifiable = false
          vim.bo[buf].filetype = "notes_mgr"
          vim.api.nvim_win_set_cursor(win, { 6, 0 })
        end

        local function map(key, func)
          vim.keymap.set("n", key, func, { buffer = buf, silent = true, nowait = true })
        end

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
          elseif line:match("") then
            local dir = line:match("%s*(.-)/?$")
            current_view_dir = current_view_dir .. "/" .. dir
            draw_ui()
          elseif line:match("") then
            local file = line:match("%s*(.-)$")
            vim.api.nvim_win_close(win, true)
            vim.cmd("e " .. vim.fn.fnameescape(current_view_dir .. "/" .. file))
          end
        end)

        map("<Space>", function()
          current_project_path = current_view_dir
          vim.notify(
            "Active Notebook set to: " .. current_project_path,
            vim.log.levels.INFO,
            { title = "Notes System" }
          )
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
          local target = line:match("%s*(.-)/?$") or line:match("%s*(.-)$")
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
          -- Strip leading/trailing whitespace and trailing slash (dirs end with /)
          local name = raw:gsub("^%s+", ""):gsub("%s+$", ""):gsub("/$", "")
          if name:match("%.md$") then
            do_export(current_view_dir, name) -- export this single file
          else
            do_export(current_view_dir, nil) -- export all .md in current dir
          end
        end)

        draw_ui()
      end

      -- Seamless Snippet Capture (Now with Topic List)
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

          -- Build list of existing topics
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

          -- Prompt user to select an existing file or create a new one
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

      vim.keymap.set("v", "<leader>ms", function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
        vim.schedule(capture_snippet)
      end, { desc = "Capture Snippet" })
    end,
  },
}
