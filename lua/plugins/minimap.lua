return {
  {
    "Isrothy/neominimap.nvim",
    enabled = true,
    lazy = false, -- Needs to load on startup to register the commands
    init = function()
      vim.g.neominimap = {
        auto_enable = false, -- Keeps the minimap off by default

        -- SCALE COMPRESSION:
        y_multiplier = 4,
        x_multiplier = 4,

        -- DIAGNOSTICS:
        -- Set to false to hide error/warning colors on the minimap by default.
        diagnostic = {
          enabled = false,
        },
      }
    end,
    keys = {
      -- Mapped to capital M and registers in the LazyVim UI menu
      { "<leader>uM", "<cmd>Neominimap toggle<cr>", desc = "Toggle Minimap" },

      -- Toggles diagnostic colors on the minimap dynamically
      {
        "<leader>uD",
        function()
          -- Fetch current config or initialize
          local config = vim.g.neominimap or {}
          config.diagnostic = config.diagnostic or {}

          -- Toggle the boolean (plugin defaults to true if nil)
          local is_enabled = config.diagnostic.enabled
          if is_enabled == nil then
            is_enabled = true
          end
          config.diagnostic.enabled = not is_enabled

          -- Reassign and refresh the minimap API to apply changes instantly
          vim.g.neominimap = config
          require("neominimap.api").refresh()

          -- Optional: subtle notification
          vim.notify("Minimap Diagnostics: " .. (config.diagnostic.enabled and "ON" or "OFF"))
        end,
        desc = "Toggle Minimap Diagnostics",
      },
    },
  },
}
