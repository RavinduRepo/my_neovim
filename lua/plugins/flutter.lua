return {
  {
    "nvim-flutter/flutter-tools.nvim",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "stevearc/dressing.nvim",
    },
    config = function()
      local flutter_path = vim.fn.exepath("flutter")
      if flutter_path == "" then
        local candidates = {
          vim.fn.expand("~/development/flutter/bin/flutter"),
          vim.fn.expand("~/flutter/bin/flutter"),
          "/opt/flutter/bin/flutter",
        }
        for _, p in ipairs(candidates) do
          if vim.fn.filereadable(p) == 1 then
            flutter_path = p
            break
          end
        end
      end

      require("flutter-tools").setup({
        flutter_path = flutter_path ~= "" and flutter_path or nil,
        ui = {
          border = "rounded",
        },
        decorations = {
          statusline = {
            app_version = true,
            device = true,
          },
        },
        debugger = {
          enabled = true,
          run_via_dap = true,
        },
        widget_guides = {
          enabled = true,
        },
      })
    end, -- Fixed the syntax error here
  },
}
