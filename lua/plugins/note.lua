return {
  {
    "nvim-telescope/telescope.nvim",
    config = function(_, opts)
      -- Initialize default Telescope setup
      require("telescope").setup(opts)

      -- Centralized notes directory
      local notes_dir = vim.fn.expand("~/Notes")
      local current_project_path = nil

      -- Helper to ensure directory exists
      local function ensure_dir(path)
        if vim.fn.isdirectory(path) == 0 then
          vim.fn.mkdir(path, "p")
        end
      end

      ensure_dir(notes_dir)

      -- 1. Project Initialization
      local function init_project()
        vim.ui.input({ prompt = "Notes Path (e.g., C++/ShellProject): " }, function(input)
          if not input or input == "" then
            return
          end
          local path = notes_dir .. "/" .. input
          ensure_dir(path)
          current_project_path = path
          vim.notify("Notes active at: " .. path, vim.log.levels.INFO, { title = "Notes System" })
        end)
      end

      -- 2. Seamless Snippet Capture
      local function capture_snippet()
        local ft = vim.bo.filetype

        -- Extract visual selection via marks
        local _, csrow, _, _ = unpack(vim.fn.getpos("'<"))
        local _, cerow, _, _ = unpack(vim.fn.getpos("'>"))
        local lines = vim.api.nvim_buf_get_lines(0, csrow - 1, cerow, false)

        if #lines == 0 then
          vim.notify("No snippet selected!", vim.log.levels.WARN, { title = "Notes System" })
          return
        end

        vim.ui.input({ prompt = "Snippet Explanation: " }, function(comment)
          if not comment then
            return
          end

          if not current_project_path then
            vim.notify("Initialize a project first (<leader>Ni)!", vim.log.levels.ERROR, { title = "Notes System" })
            return
          end

          vim.ui.input({ prompt = "Topic File (e.g., Memory_Management): " }, function(topic)
            if not topic or topic == "" then
              return
            end
            if not topic:match("%.md$") then
              topic = topic .. ".md"
            end

            local filepath = current_project_path .. "/" .. topic
            local file = io.open(filepath, "a")
            if not file then
              vim.notify("Failed to open: " .. filepath, vim.log.levels.ERROR, { title = "Notes System" })
              return
            end

            -- Silently append clean Markdown structure
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

      -- 3. PDF Export via Pandoc
      local function export_pdf()
        if not current_project_path then
          vim.notify("Initialize a project first (<leader>Ni)!", vim.log.levels.ERROR, { title = "Notes System" })
          return
        end

        vim.ui.input({ prompt = "File to export (leave blank for entire project): " }, function(topic)
          local cmd
          if topic and topic ~= "" then
            if not topic:match("%.md$") then
              topic = topic .. ".md"
            end
            local pdf_name = topic:gsub("%.md$", ".pdf")
            cmd = string.format(
              "pandoc %q -o %q",
              current_project_path .. "/" .. topic,
              current_project_path .. "/" .. pdf_name
            )
          else
            -- Concatenate all markdown files into a single master PDF
            cmd = string.format("cd %q && pandoc *.md -o Project_Notes.pdf", current_project_path)
          end

          vim.fn.jobstart(cmd, {
            on_exit = function(_, code)
              if code == 0 then
                vim.notify("PDF Export successful!", vim.log.levels.INFO, { title = "Notes System" })
              else
                vim.notify("Export failed! Is Pandoc installed?", vim.log.levels.ERROR, { title = "Notes System" })
              end
            end,
          })
        end)
      end

      -- 4. Keybinding Registration
      local wk = require("which-key")
      wk.add({
        { "<leader>N", group = "Notes" },
      })

      -- Normal Mode Maps
      vim.keymap.set("n", "<leader>Ni", init_project, { desc = "Init Note Project" })
      vim.keymap.set("n", "<leader>Ne", export_pdf, { desc = "Export Notes to PDF" })
      vim.keymap.set("n", "<leader>Nf", function()
        require("telescope.builtin").find_files({ cwd = notes_dir })
      end, { desc = "Find Notes" })
      vim.keymap.set("n", "<leader>Ng", function()
        require("telescope.builtin").live_grep({ cwd = notes_dir })
      end, { desc = "Grep Notes" })

      -- Visual Mode Map
      vim.keymap.set("v", "<leader>Ns", function()
        -- Exit visual mode instantly to lock in the '< and '> marks for the API
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", true)
        vim.schedule(capture_snippet)
      end, { desc = "Capture Snippet" })
    end,
  },
}
