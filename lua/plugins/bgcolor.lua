return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "frappe", -- Ensure Frappe is the active flavor
      transparent_background = true, -- Set to true if you want to use the terminal's black
    },
    integrations = {
      telescope = true,
      neotree = true,
      treesitter = true,
      -- Adds black background to floating windows and borders
      native_lsp = {
        enabled = true,
        virtual_text = {
          errors = { "italic" },
          hints = { "italic" },
          warnings = { "italic" },
          information = { "italic" },
        },
      },
    },
  },
}, {
  "LazyVim/LazyVim",
  opts = {
    colorscheme = "catppuccin",
  },
}
