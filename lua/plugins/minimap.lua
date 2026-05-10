return {
  {
    "Isrothy/neominimap.nvim",
    enabled = true,
    lazy = false, -- Needs to load on startup to register the commands
    init = function()
      vim.g.neominimap = {
        auto_enable = false, -- Keeps the minimap off by default
      }
    end,
    keys = {
      -- Mapped to capital M and registers in the LazyVim UI menu
      { "<leader>uM", "<cmd>Neominimap toggle<cr>", desc = "Toggle Minimap" },
    },
  },
}
