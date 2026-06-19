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

      -- Export Logic
      local function do_export(target_dir, target_file)
        local cmd
        if target_file then
          local pdf_name = target_file:gsub("%.md$", ".pdf")
          cmd = string.format("cd %q && pandoc %q -o %q", target_dir, target_file, pdf_name)
          vim.notify("Exporting " .. target_file .. "...", vim.log.levels.INFO, { title = "Notes System" })
        else
          cmd = string.format("cd %q && pandoc *.md -o _Notebook_Export.pdf", target_dir)
          vim.notify("Exporting all notes in directory...", vim.log.levels.INFO, { title = "Notes System" })
        end

        local stderr_chunks = {}
        vim.fn.jobstart({ "sh", "-c", cmd }, {
          on_stderr = function(_, data)
            for _, line in ipairs(data) do
              if line ~= "" then
                table.insert(stderr_chunks, line)
              end
            end
          end,
          on_exit = function(_, code)
            if code == 0 then
              vim.notify("PDF Export successful!", vim.log.levels.INFO, { title = "Notes System" })
            else
              local err_msg = table.concat(stderr_chunks, "\n")
              vim.notify("Pandoc failed:\n" .. err_msg, vim.log.levels.ERROR, { title = "Notes System" })
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
            local prefix = entry.type == "directory" and "    " or "    "
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
          elseif line:match("") then
            local dir = line:match("%s*(.-)/?$")
            current_view_dir = current_view_dir .. "/" .. dir
            draw_ui()
          elseif line:match("") then
            local file = line:match("%s*(.-)$")
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
          local line = vim.api.nvim_get_current_line()
          local target_file = line:match("%s*(.-)$")
          do_export(current_view_dir, target_file)
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
