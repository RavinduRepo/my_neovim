return {
  {
    "nvim-flutter/flutter-tools.nvim",
    lazy = false,
    dependencies = {
      "nvim-lua/plenary.nvim",
      "stevearc/dressing.nvim", -- Optional: makes the device selection menu look much nicer
    },
    config = function()
      require("flutter-tools").setup({
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
          enabled = true, -- Enable to integrate with nvim-dap for debugging
          run_via_dap = true,
        },
        widget_guides = {
          enabled = true, -- Adds helpful indent guides for deeply nested Flutter widgets
        },
      })
    end,
  },
}
