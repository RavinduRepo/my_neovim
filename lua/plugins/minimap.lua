return {
  {
    "Isrothy/neominimap.nvim",
    enabled = true,
    lazy = false, -- Needs to load on startup to register the commands
    init = function()
      vim.g.neominimap = {
        auto_enable = false, -- Keeps the minimap off by default

        -- SCALE COMPRESSION:
        -- How many rows of actual code a single minimap dot should span.
        -- Default is 1. Increase this to "shrink" the text vertically
        -- and see more of your file in the mini view.
        y_multiplier = 4,

        -- How many columns of code a dot should span.
        -- Default is 4. Tweak this to adjust horizontal compression.
        x_multiplier = 4,
      }
    end,
    keys = {
      -- Mapped to capital M and registers in the LazyVim UI menu
      { "<leader>uM", "<cmd>Neominimap toggle<cr>", desc = "Toggle Minimap" },
    },
  },
}
