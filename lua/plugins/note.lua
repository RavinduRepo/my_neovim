return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function(_, opts)
      require("telescope").setup(opts)

      local notes_dir = vim.fn.expand("~/Notes")
      local current_project_path = nil

      local function ensure_dir(path)
        if vim.fn.isdirectory(path) == 0 then
          vim.fn.mkdir(path, "p")
        end
      end
      ensure_dir(notes_dir)

      -- Custom Telescope Picker for finding OR creating items
      local function pick_or_create(prompt_title, root_dir, find_type, callback)
        local scan = require("plenary.scandir")
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")
        local pickers = require("telescope.pickers")
        local finders = require("telescope.finders")
        local conf = require("telescope.config").values

        local results = {}
        if vim.fn.isdirectory(root_dir) == 1 then
          scan.scan_dir(root_dir, {
            hidden = false,
            only_dirs = (find_type == "d"),
            search_pattern = (find_type == "f") and "%.md$" or nil,
            on_insert = function(entry)
              -- Keep paths relative for cleaner UI
              table.insert(results, entry:sub(#root_dir + 2))
            end,
          })
        end

        pickers
          .new({}, {
            prompt_title = prompt_title,
            finder = finders.new_table({ results = results }),
            sorter = conf.generic_sorter({}),
            attach_mappings = function(prompt_bufnr, map)
              actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                local input = action_state.get_current_line()
                actions.close(prompt_bufnr)

                -- If an existing item is highlighted, use it.
                -- Otherwise, use exactly what was typed to create a new one.
                if selection then
                  callback(selection.value)
                elseif input and input ~= "" then
                  callback(input)
                end
              end)
              return true
            end,
          })
          :find()
      end

      -- 1. Project Initialization (Fuzzy Search or Create)
      local function init_project()
        pick_or_create("Select/Create Project (e.g. C++/ShellProject)", notes_dir, "d", function(input)
          local path = notes_dir .. "/" .. input
          ensure_dir(path)
          current_project_path = path
          vim.notify("Notes active at: " .. path, vim.log.levels.INFO, { title = "Notes System" })
        end)
      end

      -- 2. Seamless Snippet Capture (Fuzzy Search or Create)
      local function capture_snippet()
        local ft = vim.bo.filetype
        local _, csrow, _, _ = unpack(vim.fn.getpos("'<"))
        local _, cerow, _, _ = unpack(vim.fn.getpos("'>"))
        local lines = vim.api.nvim_buf_get_lines(0, csrow - 1, cerow, false)

        if #lines == 0 then
          vim.notify("No snippet selected!", vim.log.levels.WARN, { title = "Notes System" })
          return
        end

        if not current_project_path then
          vim.notify("Initialize a project first (<leader>mi)!", vim.log.levels.ERROR, { title = "Notes System" })
          return
        end

        vim.ui.input({ prompt = "Snippet Explanation: " }, function(comment)
          if not comment then
            return
          end

          pick_or_create("Select/Create Topic File", current_project_path, "f", function(topic)
            if not topic:match("%.md$") then
              topic = topic .. ".md"
            end

            local filepath = current_project_path .. "/" .. topic
            local file = io.open(filepath, "a")
            if not file then
              vim.notify("Failed to open: " .. filepath, vim.log.levels.ERROR, { title = "Notes System" })
              return
            end

            file:write("\n### " .. os.date("%Y-%m-%d %H:%M") .. "\n")
            file:write(comment .. "\n\n")
            file:write("```" .. ft .. "\n")
            for _, line in ipairs(lines) do
              file:write(line .. "\n")
            end
            file:write("```\n\n---\n")
            file:close()

            vim.notify("Snippet saved to " .. topic, vim.log.levels.INFO, { title = "Notes System" })
          end)
        end)
      end

      -- 3. PDF Export via Pandoc (With Error Catching)
      local function export_pdf()
        if not current_project_path then
          vim.notify("Initialize a project first (<leader>mi)!", vim.log.levels.ERROR, { title = "Notes System" })
          return
        end

        local cmd = { "sh", "-c", "pandoc *.md -o Project_Notes.pdf" }
        local stderr_chunks = {}

        vim.notify("Exporting PDF...", vim.log.levels.INFO, { title = "Notes System" })

        vim.fn.jobstart(cmd, {
          cwd = current_project_path,
          on_stderr = function(_, data)
            for _, line in ipairs(data) do
              if line ~= "" then
                table.insert(stderr_chunks, line)
              end
            end
          end,
          on_exit = function(_, code)
            if code == 0 then
              vim.notify(
                "PDF Export successful! Saved to " .. current_project_path,
                vim.log.levels.INFO,
                { title = "Notes System" }
              )
            else
              local err_msg = table.concat(stderr_chunks, "\n")
              vim.notify("Pandoc failed:\n" .. err_msg, vim.log.levels.ERROR, { title = "Notes System" })
            end
          end,
        })
      end

      -- 4. Keybinding Registration
      local wk = require("which-key")
      wk.add({
        { "<leader>m", group = "Notes" },
      })

      -- Normal Mode Maps
      vim.keymap.set("n", "<leader>mi", init_project, { desc = "Init Note Project" })
      vim.keymap.set("n", "<leader>me", export_pdf, { desc = "Export Notes to PDF" })
      vim.keymap.set("n", "<leader>mf", function()
        require("telescope.builtin").find_files({ cwd = notes_dir })
      end, { desc = "Find Notes" })
      vim.keymap.set("n", "<leader>mg", function()
        require("telescope.builtin").live_grep({ cwd = notes_dir })
      end, { desc = "Grep Notes" })

      -- Visual Mode Map
      vim.keymap.set("v", "<leader>ms", function()
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
        vim.schedule(capture_snippet)
      end, { desc = "Capture Snippet" })
    end,
  },
}
